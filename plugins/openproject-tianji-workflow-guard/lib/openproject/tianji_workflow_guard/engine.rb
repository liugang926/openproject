# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
raise "TIANJI_RESEARCH_CANDIDATE_NOT_APPROVED_FOR_LOADING"

require "active_support/concern"
require_relative "patches/work_packages/base_contract_patch"
require_relative "patches/work_packages/update_dependent_contract_patch"

module OpenProject
  module TianjiWorkflowGuard
    class Engine < ::Rails::Engine
      engine_name :openproject_tianji_workflow_guard
      include ::OpenProject::Plugins::ActsAsOpEngine

      register "openproject-tianji-workflow-guard", requires_openproject: "= 17.9.2"
      patch_with_namespace :WorkPackages, :BaseContract
      patch_with_namespace :WorkPackages, :UpdateDependentContract

      config.after_initialize do
        ::OpenProject::TianjiWorkflowGuard::Runtime.boot!(
          config_path: ENV.fetch("TIANJI_WORKFLOW_GUARD_CONFIG"), app_root: ::Rails.root.to_s
        )
      end
    end
  end
end
