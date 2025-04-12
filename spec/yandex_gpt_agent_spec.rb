# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::YandexGptAgent do
  before(:each) do
    @valid_options = {
      'folder_id' => 'test-folder',
      'api_key' => 'test-key',
      'model_name' => 'yandexgpt-lite',
      'model_version' => 'latest',
      'system_prompt' => 'Test system prompt',
      'user_prompt' => 'Test user prompt',
      'temperature' => 0.1,
      'max_tokens' => 2000,
      'expected_receive_period_in_days' => 1
    }
    @checker = Agents::YandexGptAgent.new(name: "YandexGPTAgent", options: @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
