# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
# Synthetic decision tests only. This is not a native service/API acceptance.
require "json"
require "digest"
require_relative "../lib/openproject/tianji_workflow_guard/config"
require_relative "../lib/openproject/tianji_workflow_guard/policy"

module GuardPolicyTest
  Config = OpenProject::TianjiWorkflowGuard::Config
  Snapshot = OpenProject::TianjiWorkflowGuard::Snapshot
  Policy = OpenProject::TianjiWorkflowGuard::Policy
  module_function

  def config_data
    permissions = Config::PERMISSIONS
    read = %w[view_project_attributes view_project_phases view_work_packages]
    specifications = [
      [501, permissions, [[1, 5], [5, 6], [6, 7], [7, 13], [13, 6], [18, 7]]],
      [502, permissions - ["manage_versions"], [[6, 7], [7, 15], [18, 7]]],
      [503, read + %w[add_work_packages add_work_package_comments edit_own_work_package_comments add_work_package_attachments work_package_assigned change_work_package_status], [[15, 16], [16, 18], [17, 18]]],
      [504, read + %w[add_work_package_comments edit_own_work_package_comments], []],
      [505, read, []]
    ]
    {
      "schema_version" => "1.0.0", "openproject_version" => "17.9.2",
      "managed_project_ids" => [100], "managed_type_ids" => [8, 9, 10, 11, 12, 13],
      "default_status_id" => 1, "controlled_status_ids" => [17],
      "authoritative_custom_field_ids" => [99],
      "status_catalog" => (1..18).map { |id| { "id" => id, "is_closed" => [12, 14].include?(id), "is_default" => id == 1 } },
      "human_roles" => specifications.map do |id, grants, edges|
        { "id" => id, "permissions" => grants,
          "transitions" => { "default" => edges, "author" => [], "assignee" => [] } }
      end
    }
  end

  def base(config)
    original = { "id" => 1000, "project_id" => 100, "type_id" => 8, "status_id" => 6,
                 "lock_version" => 3, "author_id" => 200, "assigned_to_id" => 300 }
    {
      "original" => original, "target" => original.merge("status_id" => 7),
      "actor" => { "id" => 400, "active" => true, "admin" => false },
      "role_rows" => [{ "id" => 502, "type" => "ProjectRole", "permissions" => config.roles.fetch(502)["permissions"] }],
      "status_catalog" => config.statuses.values,
      "source_catalog" => [1, 5, 6, 7, 12, 13, 15, 16, 17, 18],
      "target_catalog" => [1, 5, 6, 7, 12, 13, 15, 16, 17, 18],
      "source_edges" => [7], "target_edges" => [7],
      "user_changed_fields" => ["status_id"], "all_changed_fields" => ["status_id"],
      "attachments_changed" => false, "authoritative_fields_changed" => false,
      "native_permissions" => { "add" => true, "edit" => true, "status" => true, "assign_versions" => true, "attach" => true },
      "matrix_valid" => true, "source_snapshot_current" => true
    }
  end

  def alter(base)
    data = JSON.parse(JSON.generate(base))
    yield data
    Snapshot.new(data)
  end

  def run
    config = Config.new(config_data)
    policy = Policy.new(config)
    data = base(config)
    counts = { "passed" => 0, "failed" => 0, "skipped" => 0 }
    failures = []
    check = lambda do |name, expected, snapshot, evaluator = policy|
      actual = evaluator.evaluate(snapshot)
      if expected == actual
        counts["passed"] += 1
      else
        counts["failed"] += 1
        failures << { "case" => name, "expected" => expected, "actual" => actual }
      end
    end
    check.call("developer approved status change", nil, Snapshot.new(data))
    %w[subject description].each do |field|
      check.call("ordinary open #{field} edit", nil, alter(data) { |d| d["target"] = d["original"].dup; d["user_changed_fields"] = [field]; d["all_changed_fields"] = [field] })
    end
    # Model real permission boundaries with separate approved role profiles.
    # Names below are the Authority's emitted fields, not Policy::VERSION_FIELDS.
    version_only_config_data = config_data
    version_only_config_data["human_roles"].find { |role| role["id"] == 502 }["permissions"].delete("edit_work_packages")
    version_only_config = Config.new(version_only_config_data)
    version_only_policy = Policy.new(version_only_config)
    version_only = base(version_only_config)
    version_only["target"] = version_only["original"].dup
    version_only["native_permissions"]["edit"] = false

    ordinary_only_config_data = config_data
    ordinary_only_config_data["human_roles"].find { |role| role["id"] == 502 }["permissions"].delete("assign_versions")
    ordinary_only_config = Config.new(ordinary_only_config_data)
    ordinary_only_policy = Policy.new(ordinary_only_config)
    ordinary_only = base(ordinary_only_config)
    ordinary_only["target"] = ordinary_only["original"].dup
    ordinary_only["native_permissions"]["assign_versions"] = false

    %w[subject description].each do |field|
      check.call("ordinary #{field} editing needs no version grant", nil, alter(ordinary_only) do |d|
        d["user_changed_fields"] = [field]; d["all_changed_fields"] = [field]
      end, ordinary_only_policy)
    end
    %w[target_versions observed_in_versions].each do |field|
      check.call("version-only role can assign #{field} without content editing", nil, alter(version_only) do |d|
        d["user_changed_fields"] = [field]; d["all_changed_fields"] = [field]
      end, version_only_policy)
      check.call("content editor without version grant cannot assign #{field}", :version_permission_denied, alter(ordinary_only) do |d|
        d["user_changed_fields"] = [field]; d["all_changed_fields"] = [field]
      end, ordinary_only_policy)
      check.call("#{field} grant cannot authorize a mixed subject edit", :edit_permission_denied, alter(version_only) do |d|
        d["user_changed_fields"] = [field, "subject"]; d["all_changed_fields"] = [field, "subject"]
      end, version_only_policy)
      check.call("both native grants permit open #{field} and subject edit", nil, alter(data) do |d|
        d["target"] = d["original"].dup
        d["user_changed_fields"] = [field, "subject"]; d["all_changed_fields"] = [field, "subject"]
      end)
      [12, 14, 17].each do |status|
        check.call("#{field} permission cannot enter protected #{status}", :authorization_backend_unavailable, alter(data) do |d|
          d["target"]["status_id"] = status
          d["user_changed_fields"] = [field, "status_id"]; d["all_changed_fields"] = [field, "status_id"]
        end)
        check.call("#{field} permission cannot mutate protected #{status}", :authorization_backend_unavailable, alter(data) do |d|
          d["original"]["status_id"] = status; d["target"] = d["original"].dup
          d["user_changed_fields"] = [field]; d["all_changed_fields"] = [field]
        end)
      end
      check.call("#{field} permission cannot authorize evidence mutation", :authoritative_field_readonly, alter(data) do |d|
        d["target"] = d["original"].dup; d["authoritative_fields_changed"] = true
        d["user_changed_fields"] = [field, "custom_field_99"]; d["all_changed_fields"] = [field, "custom_field_99"]
      end)
    end
    check.call("both version associations can change with only the version grant", nil, alter(version_only) do |d|
      d["user_changed_fields"] = %w[target_versions observed_in_versions]
      d["all_changed_fields"] = %w[target_versions observed_in_versions]
    end, version_only_policy)
    check.call("similar field name is not covered by the version grant", :edit_permission_denied, alter(version_only) do |d|
      d["user_changed_fields"] = ["observed_in_versions_metadata"]; d["all_changed_fields"] = ["observed_in_versions_metadata"]
    end, version_only_policy)
    [8, 9, 10, 11, 12, 13].permutation(2).each do |source, target|
      check.call("ordinary same-status type #{source}->#{target}", nil, alter(data) do |d|
        d["original"]["type_id"] = source; d["target"] = d["original"].merge("type_id" => target)
        d["user_changed_fields"] = ["type_id"]; d["all_changed_fields"] = ["type_id"]
      end)
      [12, 14, 17].each do |status|
        check.call("combined type #{source}->#{target} plus controlled #{status}", :authorization_backend_unavailable, alter(data) do |d|
          d["original"]["type_id"] = source; d["target"]["type_id"] = target; d["target"]["status_id"] = status
          d["user_changed_fields"] = %w[type_id status_id]; d["all_changed_fields"] = %w[type_id status_id]
        end)
      end
    end
    (8..13).each do |type|
      check.call("default create type #{type}", nil, alter(data) { |d| d["original"] = nil; d["target"]["id"] = nil; d["target"]["type_id"] = type; d["target"]["status_id"] = 1 })
      [5, 6, 7, 15, 16, 18].each do |status|
        check.call("nondefault create type #{type} status #{status}", :initial_status_not_default, alter(data) { |d| d["original"] = nil; d["target"]["type_id"] = type; d["target"]["status_id"] = status })
      end
      [12, 14, 17].each do |status|
        check.call("controlled create type #{type} status #{status}", :authorization_backend_unavailable, alter(data) { |d| d["original"] = nil; d["target"]["type_id"] = type; d["target"]["status_id"] = status })
      end
    end
    check.call("source matrix required", :source_transition_missing, alter(data) { |d| d["source_edges"] = [] })
    check.call("target matrix required", :target_transition_missing, alter(data) { |d| d["target_edges"] = [] })
    check.call("configured edge required despite native catalog", :approved_transition_missing, alter(data) { |d| d["original"]["status_id"] = 1 })
    check.call("type payload cannot manufacture default matrix", :approved_transition_missing, alter(data) { |d| d["original"]["status_id"] = 1; d["target"]["type_id"] = 9 })
    check.call("same type link still cannot close", :authorization_backend_unavailable, alter(data) { |d| d["target"]["status_id"] = 12 })
    check.call("unknown closed catalog drift", :status_catalog_drift, alter(data) { |d| d["status_catalog"] << { "id" => 19, "is_closed" => true, "is_default" => false }; d["target"]["status_id"] = 19 })
    check.call("known closed classification drift", :status_catalog_drift, alter(data) { |d| d["status_catalog"].find { |s| s["id"] == 7 }["is_closed"] = true })
    check.call("current database revision required", :stale_snapshot, alter(data) { |d| d["source_snapshot_current"] = false })
    check.call("actor disabled", :actor_not_approved, alter(data) { |d| d["actor"]["active"] = false })
    check.call("native administrator is not workflow authorization", :actor_not_approved, alter(data) { |d| d["actor"]["admin"] = true })
    check.call("no actor ID executor exception", :role_not_approved, alter(data) { |d| d["actor"]["id"] = 999; d["role_rows"][0]["id"] = 999 })
    check.call("unknown role combined with developer", :role_not_approved, alter(data) { |d| d["role_rows"] << { "id" => 3, "type" => "ProjectRole", "permissions" => [] } })
    check.call("global role rejected", :role_not_approved, alter(data) { |d| d["role_rows"][0]["type"] = "GlobalRole" })
    check.call("role permission drift", :role_not_approved, alter(data) { |d| d["role_rows"][0]["permissions"] << "manage_members" })
    check.call("native matrix drift", :workflow_matrix_drift, alter(data) { |d| d["matrix_valid"] = false })
    check.call("status permission required", :status_permission_denied, alter(data) { |d| d["native_permissions"]["status"] = false })
    check.call("type edit permission required", :edit_permission_denied, alter(data) { |d| d["target"]["type_id"] = 9; d["native_permissions"]["edit"] = false })
    check.call("source project escape denied", :scope_escape, alter(data) { |d| d["target"]["project_id"] = 101 })
    check.call("source type escape denied", :scope_escape, alter(data) { |d| d["target"]["type_id"] = 1 })
    check.call("unmanaged type entering protected project denied", :scope_escape, alter(data) { |d| d["original"]["type_id"] = 1 })
    check.call("managed type outside fixed project denied", :scope_escape, alter(data) { |d| d["original"]["project_id"] = 101; d["target"]["project_id"] = 101 })
    check.call("authoritative fields never caller writable", :authoritative_field_readonly, alter(data) { |d| d["authoritative_fields_changed"] = true })
    [12, 14, 17].each do |status|
      %w[subject description type_id target_versions custom_field_99].each do |field|
        check.call("protected #{status} record #{field} mutation", :authorization_backend_unavailable, alter(data) do |d|
          d["original"]["status_id"] = status; d["target"] = d["original"].dup
          d["user_changed_fields"] = [field]; d["all_changed_fields"] = [field]
        end)
      end
      check.call("protected #{status} attachment replacement", :authorization_backend_unavailable, alter(data) do |d|
        d["original"]["status_id"] = status; d["target"] = d["original"].dup
        d["user_changed_fields"] = []; d["all_changed_fields"] = []; d["attachments_changed"] = true
      end)
      check.call("protected #{status} no-change contract", nil, alter(data) do |d|
        d["original"]["status_id"] = status; d["target"] = d["original"].dup
        d["user_changed_fields"] = []; d["all_changed_fields"] = []
      end)
    end
    [12, 17].each do |status|
      check.call("new deployment reset #{status}->16 needs real backend", :authorization_backend_unavailable, alter(data) { |d| d["original"]["status_id"] = status; d["target"]["status_id"] = 16 })
    end
    check.call("tester status-only positive", nil, alter(data) do |d|
      d["original"]["status_id"] = 15; d["target"]["status_id"] = 16
      d["source_edges"] = [16]; d["target_edges"] = [16]; d["native_permissions"]["edit"] = false
      d["role_rows"] = [{ "id" => 503, "type" => "ProjectRole", "permissions" => config.roles.fetch(503)["permissions"] }]
    end)
    check.call("tester cannot edit title beside status", :edit_permission_denied, alter(data) { |d| d["user_changed_fields"] << "subject"; d["native_permissions"]["edit"] = false })
    [504, 505].each do |role|
      check.call("approver/reader #{role} cannot gain editing", :edit_permission_denied, alter(data) do |d|
        d["role_rows"] = [{ "id" => role, "type" => "ProjectRole", "permissions" => config.roles.fetch(role)["permissions"] }]
        d["target"] = d["original"].dup; d["user_changed_fields"] = ["subject"]; d["native_permissions"]["edit"] = false
      end)
    end
    [false, true].repeated_permutation(2).each do |author, assignee|
      check.call("author #{author} / assignee #{assignee} cannot add an edge", :approved_transition_missing, alter(data) do |d|
        d["original"]["author_id"] = author ? 400 : 200; d["original"]["assigned_to_id"] = assignee ? 400 : 300
        d["original"]["status_id"] = 1; d["target"]["assigned_to_id"] = 400
      end)
    end
    check.call("target type excludes preserved open status", :target_type_status_invalid, alter(data) { |d| d["target"] = d["original"].merge("type_id" => 9); d["target_catalog"] = [1] })
    check.call("ordinary legacy project unaffected", nil, alter(data) { |d| [d["original"], d["target"]].each { |r| r["project_id"] = 999; r["type_id"] = 1 } })
    mutable = JSON.parse(JSON.generate(data)); immutable = Snapshot.new(mutable)
    mutable["target"]["status_id"] = 12
    check.call("snapshot captures immutable copy", nil, immutable)
    mutations = [
      ->(c) { c["managed_project_ids"] = [] }, ->(c) { c["human_roles"] = [] },
      ->(c) { c["unknown"] = true }, ->(c) { c["default_status_id"] = 12 },
      ->(c) { c["human_roles"][0]["transitions"]["default"] << [17, 12] },
      ->(c) { c["human_roles"][0]["transitions"]["author"] << [1, 7] }
    ]
    mutations.each_with_index do |mutation, index|
      invalid = config_data; mutation.call(invalid)
      begin
        Config.new(invalid); counts["failed"] += 1; failures << { "case" => "invalid configuration #{index}", "actual" => "accepted" }
      rescue OpenProject::TianjiWorkflowGuard::ConfigurationError
        counts["passed"] += 1
      end
    end
    puts JSON.generate({ "suite" => "synthetic-ruby-policy-only", **counts, "failures" => failures,
                         "native_service_tested" => false, "production_changes" => false,
                         "authorization_backend_implemented" => false })
    exit(counts["failed"].zero? ? 0 : 1)
  end
end

GuardPolicyTest.run if $PROGRAM_NAME == __FILE__
