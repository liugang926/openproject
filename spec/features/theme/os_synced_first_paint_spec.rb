# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "OS-synced theme on first paint", :js do
  shared_let(:user) { create(:user, preferences: { theme: "sync_with_os" }) }

  def emulate_media(**features)
    page.driver.browser.page.command(
      "Emulation.setEmulatedMedia",
      features: features.map { |name, value| { name: name.to_s.tr("_", "-"), value: } }
    )
  end

  def without_external_scripts
    browser = page.driver.browser
    browser.network.intercept(resource_type: "Script")
    handler = browser.on(:request) { |request, *| request.abort }
    yield
  ensure
    browser.page.off(:request, handler)
    browser.page.command("Fetch.disable")
  end

  it "resolves a dark OS to the dark theme on the login page" do
    User.anonymous.pref.update!(settings: { "theme" => "sync_with_os" })
    emulate_media(prefers_color_scheme: "dark")
    visit signin_path

    expect(page).to have_css("body > script", text: "prefers-color-scheme", visible: :all)
    expect(page).to have_css("body[data-color-mode='dark'][data-dark-theme='dark']")
  end

  it "resolves a dark OS asking for more contrast to dark high contrast" do
    login_as user
    emulate_media(prefers_color_scheme: "dark", prefers_contrast: "more")
    visit home_path

    expect(page).to have_css("body > script", text: "prefers-contrast", visible: :all)
    expect(page).to have_css("body[data-color-mode='dark'][data-dark-theme='dark_high_contrast']")
  end

  it "applies the forced dark contrast preference from the inline script alone" do
    user.pref.update!(settings: user.pref.settings.merge("force_dark_theme_contrast" => true))
    login_as user
    emulate_media(prefers_color_scheme: "dark")

    without_external_scripts do
      visit home_path

      expect(page).to have_css("body[data-color-mode='dark'][data-dark-theme='dark_high_contrast']")
    end
  end
end
