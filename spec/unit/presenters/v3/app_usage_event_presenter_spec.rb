require 'spec_helper'
require 'presenters/v3/app_usage_event_presenter'

RSpec.describe VCAP::CloudController::Presenters::V3::AppUsageEventPresenter do
  let(:usage_event) { VCAP::CloudController::AppUsageEvent.make }

  describe '#to_hash' do
    let(:result) { described_class.new(usage_event).to_hash }

    it 'presents the usage event' do
      expect(result[:guid]).to eq(usage_event.guid)
      expect(result[:created_at]).to eq(usage_event.created_at)
      expect(result[:updated_at]).to eq(usage_event.created_at)
      expect(result[:data][:state][:current]).to eq usage_event.state
      expect(result[:data][:state][:previous]).to eq nil
      expect(result[:data][:app][:guid]).to eq usage_event.parent_app_guid
      expect(result[:data][:app][:name]).to eq usage_event.parent_app_name
      expect(result[:data][:process][:guid]).to eq usage_event.app_guid
      expect(result[:data][:process][:type]).to eq usage_event.process_type
      expect(result[:data][:space][:guid]).to eq usage_event.space_guid
      expect(result[:data][:space][:name]).to eq usage_event.space_name
      expect(result[:data][:organization][:guid]).to eq usage_event.org_guid
      expect(result[:data][:organization][:name]).to eq nil
      expect(result[:data][:buildpack][:guid]).to eq usage_event.buildpack_guid
      expect(result[:data][:buildpack][:name]).to eq usage_event.buildpack_name
      expect(result[:data][:task][:guid]).to eq nil
      expect(result[:data][:task][:name]).to eq nil
      expect(result[:data][:memory_in_mb_per_instance][:current]).to eq usage_event.memory_in_mb_per_instance
      expect(result[:data][:memory_in_mb_per_instance][:previous]).to eq nil
      expect(result[:data][:instance_count][:current]).to eq usage_event.instance_count
      expect(result[:data][:instance_count][:previous]).to eq nil
    end

    context 'when the usage event is for a task' do
      let(:usage_event) do
        VCAP::CloudController::AppUsageEvent.make(
          app_guid: '',
          process_type: nil,
          task_guid: 'task-guid',
          task_name: 'some-task',
        )
      end

      it 'it displays null for the process.guid' do
        expect(result[:guid]).to eq usage_event.guid
        expect(result[:data][:process][:guid]).to eq nil
        expect(result[:data][:process][:type]).to eq nil
        expect(result[:data][:task][:guid]).to eq 'task-guid'
        expect(result[:data][:task][:name]).to eq 'some-task'
      end
    end
  end
end
