# frozen_string_literal: true
# SPDX-License-Identifier: GPL-3.0-only
Gem::Specification.new do |spec|
  spec.name = "openproject-tianji-workflow-guard"
  spec.version = "0.1.0"
  spec.summary = "Independent contract guard for the TianJi managed OpenProject workflow"
  spec.authors = ["TianJi DevOps"]
  spec.license = "GPL-3.0-only"
  spec.homepage = "https://github.com/liugang926/tianji-devops-platform"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "config/**/*", "README.md", "IMPLEMENTATION-PLAN.md"]
  spec.require_paths = ["lib"]
end
