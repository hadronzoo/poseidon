class TestCluster
  attr_reader :broker, :zookeeper
  def initialize
    @zookeeper = ZookeeperRunner.new
    @broker = BrokerRunner.new(0, 9092)
  end

  def start
    @zookeeper.start
    @broker.start
  end

  def stop
    # The broker will end up in a state where it ignores SIGTERM
    # if zookeeper is stopped before the broker.
    @broker.stop
    sleep 5

    @zookeeper.stop
  end
end

class JavaRunner
  def self.remove_tmp
    FileUtils.rm_rf("#{POSEIDON_PATH}/tmp")
  end

  def self.set_kafka_path!
    if ENV['KAFKA_PATH']
      JavaRunner.kafka_path = ENV['KAFKA_PATH']
    else
      puts "******To run integration specs you must set KAFKA_PATH to kafka src directory. See README*****"
      exit
    end
  end

  def self.kafka_path=(kafka_path)
    @kafka_path = kafka_path
  end

  def self.kafka_path
    @kafka_path
  end

  def initialize(id, start_cmd, stop_cmd, properties = {})
    @id = id
    @properties = properties
    @start_cmd = start_cmd
    @stop_cmd = stop_cmd
  end

  def start
    write_properties
    run
  end

  def stop
    `#{@stop_cmd}`
  end

  def without_process
    stop
    sleep 5
    begin
      yield
    ensure
      start
      sleep 5
    end
  end

  private

  def run
    FileUtils.mkdir_p(log_dir)
    `LOG_DIR=#{log_dir} #{@start_cmd} #{config_path}`
  end

  def write_properties
    FileUtils.mkdir_p(config_dir)
    File.open(config_path, "w+") do |f|
      @properties.each do |k,v|
        f.puts "#{k}=#{v}"
      end
    end
  end

  def log_dir
    "#{file_path}/log"
  end

  def config_path
    "#{config_dir}/#{@id}.properties"
  end

  def config_dir
    "#{file_path}/config"
  end

  def file_path
    POSEIDON_PATH + "/tmp/"
  end
end

class BrokerRunner
  DEFAULT_PROPERTIES = {
    "broker.id" => 0,
    "port" => 9092,
    "num.network.threads" => 2,
    "num.io.threads" => 2,
    "socket.send.buffer.bytes" => 1048576,
    "socket.receive.buffer.bytes" => 1048576,
    "socket.request.max.bytes" => 104857600,
    "log.dir" => "#{POSEIDON_PATH}/tmp/kafka-logs",
    "num.partitions" => 1,
    "log.flush.interval.messages" => 10000,
    "log.flush.interval.ms" => 1000,
    "log.retention.hours" => 168,
    "log.segment.bytes" => 536870912,
    "log.cleanup.interval.mins" => 1,
    "zookeeper.connect" => "localhost:2181",
    "zookeeper.connection.timeout.ms" => 1000000,
    "kafka.metrics.polling.interval.secs" => 5,
    "kafka.metrics.reporters" => "kafka.metrics.KafkaCSVMetricsReporter",
    "kafka.csv.metrics.dir" => "#{POSEIDON_PATH}/tmp/kafka_metrics",
    "kafka.csv.metrics.reporter.enabled" => "false",
  }

  def initialize(id, port, partition_count = 1)
    @id   = id
    @port = port
    @jr = JavaRunner.new("broker_#{id}", 
                         "#{ENV['KAFKA_PATH']}/bin/kafka-run-class.sh -daemon -name broker_#{id} kafka.Kafka",
                         "ps ax | grep -i 'kafka\.Kafka' | grep java | grep broker_#{id} | grep -v grep | awk '{print $1}' | xargs kill -SIGTERM",
                         DEFAULT_PROPERTIES.merge(
                           "broker.id" => id,
                           "port" => port,
                           "log.dir" => "#{POSEIDON_PATH}/tmp/kafka-logs_#{id}",
                           "num.partitions" => partition_count
                         ))
  end

  def start
    @jr.start
  end

  def stop
    @jr.stop
  end

  def without_process
    @jr.without_process { yield }
  end
end


class ZookeeperRunner
  def initialize
    @jr = JavaRunner.new("zookeeper",
                         "#{ENV['KAFKA_PATH']}/bin/zookeeper-server-start.sh -daemon",
                         "ps ax | grep -i 'zookeeper' | grep -v grep | awk '{print $1}' | xargs kill -SIGTERM",
                         :dataDir => "#{POSEIDON_PATH}/tmp/zookeeper",
                         :clientPort => 2181,
                         :maxClientCnxns => 0)
  end

  def pid
    @jr.pid
  end
  
  def start
    @jr.start
  end

  def stop
    @jr.stop
  end
end
