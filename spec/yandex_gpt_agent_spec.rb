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
    @checker = Agents::YandexGptAgent.new(name: "YandexGPT Test", options: @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  describe "#validate_options" do
    it "should validate required options" do
      expect(@checker).to be_valid

      @checker.options['folder_id'] = nil
      expect(@checker).not_to be_valid
    end
  end

  describe "#receive" do
    it "should save operation id to memory" do
      event = Event.new(payload: {'message' => 'test'})
      stub_request(:post, /llm.api.cloud.yandex.net/)
        .to_return(body: {id: 'test-op-id'}.to_json)

      @checker.receive([event])
      expect(@checker.memory['pending_operations']).to have_key('test-op-id')
    end
  end

  pending "add more specs for check method and response handling"
end
