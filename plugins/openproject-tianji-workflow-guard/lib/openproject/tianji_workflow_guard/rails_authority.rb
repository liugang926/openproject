# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
module OpenProject
  module TianjiWorkflowGuard
    class AuthorityUnavailable < StandardError; end

    class RailsAuthority
      def initialize(config) = (@config = config)

      def managed_candidate?(model)
        pairs = [[model.project_id, model.type_id]]
        if model.persisted?
          pairs << [model.attribute_in_database("project_id"), model.attribute_in_database("type_id")]
        end
        pairs.any? { |project_id, type_id| @config.projects.include?(project_id) || @config.types.include?(type_id) }
      end

      def capture(model:, user:)
        raise AuthorityUnavailable, "MODEL_TYPE_UNSUPPORTED" unless model.is_a?(::WorkPackage)

        original = ::WorkPackage.find(model.id) if model.persisted?
        actor = ::User.find(user.id)
        # A fresh instance has no per-request project-role/permission cache yet.
        source = original || model
        project = source.project
        roles = original ? actor.roles_for_work_package(source).to_a : actor.roles_for_project(project).to_a
        roles = roles.uniq(&:id)
        central_context = original || project
        central_ids = ::Authorization.roles(actor, central_context).pluck(:id).uniq.sort
        raise AuthorityUnavailable, "ROLE_SCOPE_DISAGREEMENT" unless roles.map(&:id).sort == central_ids

        source_variant = source.type_variant
        target_variant = model.type_variant
        role_ids = roles.map(&:id)
        author = original && original.author_id == actor.id
        assignee = original && original.assigned_to_id == actor.id
        status = original&.status_id
        changed = model.changed_with_custom_fields.map(&:to_s).uniq
        user_changed = if model.respond_to?(:changed_by_user)
                         model.changed_by_user.map(&:to_s).uniq
                       else
                         changed
                       end
        # Replacement associations are not necessarily in ActiveRecord#changed.
        changed += ["target_versions"] if model.target_versions_changed?
        changed += ["observed_in_versions"] if model.observed_in_versions_changed?
        user_changed += ["target_versions"] if model.target_versions_changed? && !model.system_version_override?("target")
        user_changed += ["observed_in_versions"] if model.observed_in_versions_changed? && !model.system_version_override?("observed_in")
        attachments = !model.attachments_replacements.nil?
        authoritative_change = authoritative_change?(model, changed)

        Snapshot.new(
          "original" => original && record(original),
          "target" => record(model),
          "actor" => { "id" => actor.id, "active" => actor.active?, "admin" => actor.admin? },
          "role_rows" => roles.map { |role| { "id" => role.id, "type" => role.type,
                                             "permissions" => role.permissions.map(&:to_s).uniq.sort } },
          "status_catalog" => ::Status.order(:id).pluck(:id, :is_closed, :is_default).map do |id, closed, default|
            { "id" => id, "is_closed" => closed, "is_default" => default }
          end,
          "source_catalog" => statuses(source_variant), "target_catalog" => statuses(target_variant),
          "source_edges" => edges(source_variant, status, role_ids, author:, assignee:),
          "target_edges" => edges(target_variant, status, role_ids, author:, assignee:),
          "user_changed_fields" => user_changed.uniq.sort,
          "all_changed_fields" => changed.uniq.sort,
          "attachments_changed" => attachments,
          "authoritative_fields_changed" => authoritative_change,
          "native_permissions" => {
            "add" => actor.allowed_in_project?(:add_work_packages, model.project),
            "edit" => original ? actor.allowed_in_work_package?(:edit_work_packages, original) : false,
            "status" => actor.allowed_in_project?(:change_work_package_status, project),
            "assign_versions" => actor.allowed_in_project?(:assign_versions, project),
            "attach" => original ? actor.allowed_in_work_package?(:add_work_package_attachments, original) :
              actor.allowed_in_project?(:add_work_package_attachments, project)
          },
          "matrix_valid" => matrix_matches?(source_variant) && matrix_matches?(target_variant),
          "source_snapshot_current" => !original || current?(model, original)
        )
      end

      private

      def record(model)
        { "id" => model.id, "project_id" => model.project_id, "type_id" => model.type_id,
          "status_id" => model.status_id, "lock_version" => model.lock_version,
          "author_id" => model.author_id, "assigned_to_id" => model.assigned_to_id }
      end

      def current?(model, original)
        %w[project_id type_id status_id author_id assigned_to_id lock_version].all? do |attribute|
          model.attribute_in_database(attribute) == original.public_send(attribute)
        end
      end

      def statuses(variant)
        return [] unless variant

        variant.statuses(include_default: true).pluck(:id).uniq.sort
      end

      def edges(variant, old_status, role_ids, author:, assignee:)
        return [] unless variant && old_status

        variant.workflows.from_status(old_status, role_ids, author: !!author, assignee: !!assignee)
               .pluck(:new_status_id).uniq.sort
      end

      def matrix_matches?(variant)
        return false unless variant

        @config.roles.all? do |id, role|
          actual = variant.workflows.where(role_id: id).pluck(:old_status_id, :new_status_id, :author, :assignee).sort
          approved = role["transitions"].flat_map do |kind, transitions|
            transitions.map { |old_id, new_id| [old_id, new_id, kind == "author", kind == "assignee"] }
          end.sort
          actual == approved
        end
      end

      def authoritative_change?(model, fields)
        @config.authoritative_custom_field_ids.any? do |id|
          fields.include?("custom_field_#{id}") || model.custom_values.any? do |value|
            value.custom_field_id == id && (value.changed? || value.marked_for_destruction?)
          end
        end
      end
    end
  end
end
