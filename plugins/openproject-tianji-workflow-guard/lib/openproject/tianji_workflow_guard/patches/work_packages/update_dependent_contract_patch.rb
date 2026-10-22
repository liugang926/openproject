# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
module OpenProject
  module TianjiWorkflowGuard
    module Patches
      module WorkPackages
        module DependentValidation
          # Upstream 17.9.2 intentionally returns true here; its callbacks never run.
          # Preserve that behavior for unrelated checks, then add our independent gate.
          def validate(...)
            native_valid = super
            guard_valid = ::OpenProject::TianjiWorkflowGuard::Runtime.validate(model:, user:)
            native_valid && guard_valid && errors.empty?
          end
        end

        module UpdateDependentContractPatch
          extend ActiveSupport::Concern
          included do
            prepend ::OpenProject::TianjiWorkflowGuard::Patches::WorkPackages::DependentValidation
          end
        end
      end
    end
  end
end
