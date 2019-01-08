require File.expand_path('../test_helper', __FILE__)
require File.expand_path('../fixtures/test_jobs', __FILE__)
require File.expand_path('../fixtures/hooked', __FILE__)

describe "Backburner::Worker module" do
  before do
    Backburner.default_queues.clear
    clear_jobs!(Backburner.configuration.primary_queue, "test-plain", "test.bar", "bar.baz.foo")
  end

  describe "for enqueue class method" do
    it "should support enqueuing plain job" do
      Backburner::Worker.enqueue TestPlainJob, [7, 9], :ttr => 100, :pri => 2000
      pop_one_job("test-plain") do |job, body|
        assert_equal "TestPlainJob", body["class"]
        assert_equal [7, 9], body["args"]
        assert_equal 100, job.ttr
        assert_equal 2000, job.pri
      end
    end # plain

    it "should support enqueuing job with class queue priority" do
      Backburner::Worker.enqueue TestJob, [3, 4], :ttr => 100
      pop_one_job do |job, body|
        assert_equal "TestJob", body["class"]
        assert_equal [3, 4], body["args"]
        assert_equal 100, job.ttr
        assert_equal 100, job.pri
      end
    end # queue priority

    it "should support enqueuing job with specified named priority" do
      Backburner::Worker.enqueue TestJob, [3, 4], :ttr => 100, :pri => 'high'
      pop_one_job do |job, body|
        assert_equal "TestJob", body["class"]
        assert_equal [3, 4], body["args"]
        assert_equal 100, job.ttr
        assert_equal 0, job.pri
      end
    end # queue named priority

    it "should support enqueuing job with class queue respond_timeout" do
      Backburner::Worker.enqueue TestJob, [3, 4]
      pop_one_job do |job, body|
        assert_equal "TestJob", body["class"]
        assert_equal [3, 4], body["args"]
        assert_equal 300, job.ttr
        assert_equal 100, job.pri
      end
    end # queue respond_timeout

    it "should support enqueuing job with custom queue" do
      Backburner::Worker.enqueue TestJob, [6, 7], :queue => "test.bar", :pri => 5000
      pop_one_job("test.bar") do |job, body|
        assert_equal "TestJob", body["class"]
        assert_equal [6, 7], body["args"]
        assert_equal 0, job.delay
        assert_equal 5000, job.pri
        assert_equal 300, job.ttr
      end
    end # custom

    it "should support async job" do
      TestAsyncJob.async(:ttr => 100, :queue => "bar.baz.foo").foo(10, 5)
      pop_one_job("bar.baz.foo") do |job, body|
        assert_equal "TestAsyncJob", body["class"]
        assert_equal [nil, "foo", 10, 5], body["args"]
        assert_equal 100, job.ttr
        assert_equal Backburner.configuration.default_priority, job.pri
      end
    end # async

    it "should support enqueueing job with lambda queue" do
      expected_queue_name = TestLambdaQueueJob.calculated_queue_name
      Backburner::Worker.enqueue TestLambdaQueueJob, [6, 7], :queue => lambda { |klass| klass.calculated_queue_name }
      pop_one_job(expected_queue_name) do |job, body|
        assert_equal "TestLambdaQueueJob", body["class"]
        assert_equal [6, 7], body["args"]
      end
    end
  end # enqueue

  describe "for start class method" do
    it "should initialize and start the worker instance" do
      ech = stub
      Backburner::Worker.expects(:new).with("foo").returns(ech)
      ech.expects(:start)
      Backburner::Worker.start("foo")
    end
  end # start

  describe "for tube_names accessor" do
    before do
      Backburner.default_queues << "baz"
      Backburner.default_queues << "bam"
    end

    it "supports retrieving tubes" do
      worker = Backburner::Worker.new(["foo", "bar"])
      assert_equal ["foo", "bar"], worker.tube_names
    end

    it "supports single tube array arg" do
      worker = Backburner::Worker.new([["foo", "bar"]])
      assert_equal ["foo", "bar"], worker.tube_names
    end

    it "supports empty nil array arg with default values" do
      worker = Backburner::Worker.new([nil])
      assert_equal ['baz', 'bam'], worker.tube_names
    end

    it "supports single tube arg" do
      worker = Backburner::Worker.new("foo")
      assert_equal ["foo"], worker.tube_names
    end

    it "supports empty array arg with default values" do
      worker = Backburner::Worker.new([])
      assert_equal ['baz', 'bam'], worker.tube_names
    end

    it "supports nil arg with default values" do
      worker = Backburner::Worker.new(nil)
      assert_equal ['baz', 'bam'], worker.tube_names
    end
  end # tube_names

  describe "for work_one_job" do
    it "should raise when not connected to beanstalkd" do
      worker = Backburner::Worker.new
      class FakeConnection
        def method_missing(m, *args, &block); raise Beaneater::NotConnected; end
      end

      assert_raises Beaneater::NotConnected do
        capture_stdout { worker.work_one_job(FakeConnection.new) }
      end
    end
  end

  describe "for custom serialization" do
    before do
      Backburner.configure do |config|
        @old_parser = config.job_parser_proc
        @old_serializer = config.job_serializer_proc
        config.job_parser_proc = lambda { |body| Marshal.load(body) }
        config.job_serializer_proc = lambda { |body| Marshal.dump(body) }
      end
    end

    after do
      clear_jobs!('test-plain')
      Backburner.configure do |config|
        config.job_parser_proc = @old_parser
        config.job_serializer_proc = @old_serializer
      end
    end

    it "should support enqueuing a job" do
      Backburner::Worker.enqueue TestPlainJob, [7, 9], :ttr => 100, :pri => 2000
      pop_one_job("test-plain") do |job, body|
        assert_equal "TestPlainJob", body[:class]
        assert_equal [7, 9], body[:args]
        assert_equal 100, job.ttr
        assert_equal 2000, job.pri
      end
    end
  end # custom serialization
end # Backburner::Worker
