require "travis/logs"
require "travis/support"
require "travis/logs/services/process_log_part"
require "travis/logs/helpers/database"
require "travis/logs/helpers/reporting"

class FakeDatabase
  attr_reader :logs, :log_parts

  def initialize
    @logs = []
    @log_parts = []
  end

  def create_log(job_id)
    log_id = @logs.length + 1
    @logs << { id: log_id, job_id: job_id, content: "" }
    log_id
  end

  def create_log_part(params)
    log_part_id = @log_parts.length + 1
    @log_parts << params
    log_part_id
  end

  def log_for_job_id(job_id)
    @logs.find { |log| log[:job_id] == job_id }
  end
end

module Travis::Logs::Services
  describe ProcessLogPart do
    let(:payload) { { "id" => 2, "log" => "hello, world", "number" => 1 } }
    let(:database) { FakeDatabase.new }

    let(:service) { described_class.new(payload, database) }

    context "without an existing log" do
      it "creates a log" do
        service.run

        expect(database.log_for_job_id(payload["id"])).not_to be_nil
      end
    end

    context "with an existing log" do
      before(:each) do
        database.create_log(payload["id"])
      end

      it "does not create another log" do
        service.run

        expect(database.logs.count { |log| log[:job_id] == payload["id"] }).to eq(1)
      end
    end

    it "creates a log part" do
      service.run

      expect(database.log_parts.last).to include(content: "hello, world", number: 1, final: false)
    end

    it "notifies pusher" do
      pusher_channel = double("pusher_channel", trigger: nil)
      pusher_client = double("pusher_client", :[] => pusher_channel)
      allow(Travis::Logs.config).to receive(:pusher_client) { pusher_client }

      service.run

      pusher_client.should have_received(:[]).with("job-#{payload["id"]}")
      pusher_channel.should have_received(:trigger).with("job:log", { "id" => payload["id"], "_log" => payload["log"], "number" => payload["number"], "final" => false })
    end
  end
end
