# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
module OpenProject
  module TianjiWorkflowGuard
    class ConfigurationError < StandardError; end

    # Only a protected deployment file is parsed; no controller accepts this data.
    class Config
      KEYS = %w[schema_version openproject_version managed_project_ids managed_type_ids
                default_status_id controlled_status_ids status_catalog human_roles
                authoritative_custom_field_ids].freeze
      PERMISSIONS = %w[view_project_attributes view_project_phases view_work_packages
                       add_work_packages edit_work_packages add_work_package_comments
                       edit_own_work_package_comments add_work_package_attachments
                       assign_versions work_package_assigned manage_versions
                       change_work_package_status].freeze
      TRANSITIONS = %w[default author assignee].freeze
      attr_reader :projects, :types, :default_status_id, :controlled_status_ids,
                  :statuses, :roles, :authoritative_custom_field_ids, :revision

      def self.load(path)
        stat = File.lstat(path)
        raise ConfigurationError, "CONFIG_FILE_UNTRUSTED" unless stat.file? && !stat.symlink? &&
          stat.nlink == 1 && [0, Process.euid].include?(stat.uid) && (stat.mode & 0o022).zero? && stat.size <= 131_072

        new(JSON.parse(File.binread(path), create_additions: false))
      rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES
        raise ConfigurationError, "CONFIG_UNAVAILABLE"
      end

      def initialize(data)
        exact(data, KEYS)
        need(data["schema_version"] == "1.0.0" && data["openproject_version"] == "17.9.2")
        @projects = ids(data["managed_project_ids"], min: 1, max: 128)
        @types = ids(data["managed_type_ids"], min: 6, max: 6)
        need(@types == [8, 9, 10, 11, 12, 13])
        @default_status_id = data["default_status_id"]
        @controlled_status_ids = ids(data["controlled_status_ids"], min: 1, max: 1)
        need(@default_status_id == 1 && @controlled_status_ids == [17])
        @authoritative_custom_field_ids = ids(data["authoritative_custom_field_ids"], min: 0, max: 128)

        need(data["status_catalog"].is_a?(Array) && data["status_catalog"].length.between?(1, 256))
        @statuses = {}
        data["status_catalog"].each do |row|
          exact(row, %w[id is_closed is_default])
          need(positive?(row["id"]) && boolean?(row["is_closed"]) && boolean?(row["is_default"]))
          need(!@statuses.key?(row["id"]))
          @statuses[row["id"]] = row.dup.freeze
        end
        need(@statuses.key?(1) && !@statuses[1]["is_closed"] && @statuses[1]["is_default"])
        need(@statuses.values.count { |row| row["is_default"] } == 1)
        need(@statuses.key?(17) && !@statuses[17]["is_closed"])
        need(@statuses.values.any? { |row| row["is_closed"] })

        need(data["human_roles"].is_a?(Array) && data["human_roles"].length == 5)
        @roles = {}
        data["human_roles"].each do |row|
          exact(row, %w[id permissions transitions])
          need(positive?(row["id"]) && !@roles.key?(row["id"]))
          permissions = strings(row["permissions"])
          need((permissions - PERMISSIONS).empty? && permissions.include?("view_work_packages"))
          exact(row["transitions"], TRANSITIONS)
          transitions = row["transitions"].transform_values do |edges|
            need(edges.is_a?(Array) && edges.length <= 256)
            need(edges.uniq.length == edges.length)
            edges.each do |edge|
              need(edge.is_a?(Array) && edge.length == 2 && edge.all? { |id| @statuses.key?(id) })
              need(edge[0] != edge[1] && !@statuses[edge[1]]["is_closed"] && !@controlled_status_ids.include?(edge[1]))
            end
            edges.map { |edge| edge.dup.freeze }.sort.freeze
          end
          # The approved v1 roles have no author/assignee additional grants.
          need(transitions["author"].empty? && transitions["assignee"].empty?)
          need(transitions.values.all?(&:empty?) || permissions.include?("change_work_package_status"))
          @roles[row["id"]] = { "id" => row["id"], "permissions" => permissions.freeze,
                                "transitions" => transitions.freeze }.freeze
        end
        @revision = Digest::SHA256.hexdigest(JSON.generate(data))
        [@projects, @types, @controlled_status_ids, @authoritative_custom_field_ids, @statuses, @roles].each(&:freeze)
        freeze
      end

      def protected_status?(id)
        statuses[id]&.fetch("is_closed") || controlled_status_ids.include?(id)
      end

      def allowed_edge?(role_ids, old_status, target_status, author:, assignee:)
        role_ids.any? do |role_id|
          matrices = roles.fetch(role_id).fetch("transitions")
          edges = matrices["default"] + (author ? matrices["author"] : []) + (assignee ? matrices["assignee"] : [])
          edges.include?([old_status, target_status])
        end
      end

      private

      def exact(value, keys)
        need(value.is_a?(Hash) && value.keys.sort == keys.sort)
      end

      def positive?(value) = value.is_a?(Integer) && value.positive?
      def boolean?(value) = value == true || value == false
      def need(value) = (raise ConfigurationError, "CONFIG_INVALID" unless value)

      def ids(value, min:, max:)
        need(value.is_a?(Array) && value.length.between?(min, max) && value.all? { |id| positive?(id) } && value.uniq == value)
        value.sort.freeze
      end

      def strings(value)
        need(value.is_a?(Array) && value.length <= 64 && value.all? { |item| item.is_a?(String) && PERMISSIONS.include?(item) })
        need(value.uniq == value)
        value.map { |item| item.dup.freeze }.sort
      end
    end
  end
end
