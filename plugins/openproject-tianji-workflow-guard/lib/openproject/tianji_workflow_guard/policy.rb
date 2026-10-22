# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
module OpenProject
  module TianjiWorkflowGuard
    # A private in-process value, constructed from RailsAuthority, never HTTP input.
    class Snapshot
      KEYS = %w[original target actor role_rows status_catalog source_catalog target_catalog
                source_edges target_edges user_changed_fields all_changed_fields attachments_changed
                authoritative_fields_changed native_permissions matrix_valid source_snapshot_current].freeze
      attr_reader :data

      def initialize(data)
        raise ArgumentError, "SNAPSHOT_INVALID" unless data.is_a?(Hash) && data.keys.sort == KEYS.sort

        @data = copy(data)
        freeze
      end

      def [](key) = data.fetch(key)

      private

      def copy(value)
        case value
        when Hash then value.to_h { |key, item| [key.dup.freeze, copy(item)] }.freeze
        when Array then value.map { |item| copy(item) }.freeze
        when String then value.dup.freeze
        when Integer, TrueClass, FalseClass, NilClass then value
        else raise ArgumentError, "SNAPSHOT_VALUE_INVALID"
        end
      end
    end

    class Policy
      STATUS_FIELDS = %w[status_id].freeze
      VERSION_FIELDS = %w[target_version_ids target_versions observed_in_versions
                          override_target_versions target_version_ids_replacements].freeze

      def initialize(config) = (@config = config)

      # nil means no additional denial; upstream native authorization still applies.
      # No allowed executor branch exists until a separately reviewed backend exists.
      def evaluate(snapshot)
        return :snapshot_invalid unless snapshot.is_a?(Snapshot)

        old = snapshot["original"]
        target = snapshot["target"]
        return nil unless [old, target].compact.any? { |row| managed?(row) }
        return :scope_escape unless @config.projects.include?(target["project_id"]) && @config.types.include?(target["type_id"])
        if old
          return :scope_escape unless old["project_id"] == target["project_id"] && @config.types.include?(old["type_id"])
          return :stale_snapshot unless snapshot["source_snapshot_current"]
        end

        return :status_catalog_drift unless catalog(snapshot["status_catalog"]) == @config.statuses
        return :status_unknown unless @config.statuses.key?(target["status_id"])
        return :status_unknown if old && !@config.statuses.key?(old["status_id"])
        actor = snapshot["actor"]
        return :actor_not_approved unless actor["active"] == true && actor["admin"] == false
        roles = snapshot["role_rows"]
        return :role_not_approved if roles.empty? || roles.any? { |role| !role_matches?(role) }
        return :workflow_matrix_drift unless snapshot["matrix_valid"]
        return :authoritative_field_readonly if snapshot["authoritative_fields_changed"]

        # Any real closed flag and observation status is controlled, even on create.
        if !old || target["status_id"] != old["status_id"]
          return :authorization_backend_unavailable if @config.protected_status?(target["status_id"])
        end
        if old && @config.protected_status?(old["status_id"])
          # Unchanged read/comment contracts can still pass their native permissions.
          return :authorization_backend_unavailable if snapshot["all_changed_fields"].any? || snapshot["attachments_changed"]
        end

        permissions = snapshot["native_permissions"]
        unless old
          return :initial_status_not_default unless target["status_id"] == @config.default_status_id
          return :create_permission_denied unless permissions["add"]
          return :target_type_status_invalid unless snapshot["target_catalog"].include?(target["status_id"])

          return nil
        end

        changed = snapshot["user_changed_fields"]
        status_changed = target["status_id"] != old["status_id"]
        type_changed = target["type_id"] != old["type_id"]
        return :edit_permission_denied if type_changed && !permissions["edit"]
        if snapshot["attachments_changed"] && !permissions["attach"]
          return :attachment_permission_denied
        end
        remaining = changed - STATUS_FIELDS - VERSION_FIELDS
        return :edit_permission_denied if remaining.any? && !permissions["edit"]
        return :version_permission_denied if (changed & VERSION_FIELDS).any? && !permissions["assign_versions"]
        if type_changed
          return :target_type_status_invalid unless snapshot["target_catalog"].include?(target["status_id"])
        end
        return nil unless status_changed
        return :status_permission_denied unless permissions["status"]

        role_ids = roles.map { |role| role.fetch("id") }
        author = old["author_id"] == actor["id"]
        assignee = old["assigned_to_id"] == actor["id"]
        unless @config.allowed_edge?(role_ids, old["status_id"], target["status_id"], author:, assignee:)
          return :approved_transition_missing
        end
        return :source_transition_missing unless snapshot["source_edges"].include?(target["status_id"])
        return :target_transition_missing unless snapshot["target_edges"].include?(target["status_id"])

        nil
      rescue KeyError, TypeError, NoMethodError, ArgumentError
        :snapshot_invalid
      end

      private

      def managed?(row)
        @config.projects.include?(row["project_id"]) || @config.types.include?(row["type_id"])
      end

      def catalog(rows)
        return nil unless rows.is_a?(Array) && rows.map { |row| row["id"] }.uniq.length == rows.length

        rows.to_h { |row| [row.fetch("id"), row] }
      end

      def role_matches?(actual)
        approved = @config.roles[actual["id"]]
        approved && actual["type"] == "ProjectRole" && actual["permissions"].sort == approved["permissions"]
      end
    end
  end
end
