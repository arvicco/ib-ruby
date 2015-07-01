require 'rspec'
require 'rspec/its'
require 'ib'
require 'pp'

# Configure top level option indicating how the test suite should be run

OPTS ||= {
  :verbose => false, #true, # Run test suite in a verbose mode ?
  :rails => IB.rails? && Rails.application.class.parent_name,
  :db => IB.db_backed?
}

# Connection to your IB PAPER ACCOUNT
ACCOUNT ||= 'DU248504' # Set this to your Paper Account Number
HOST ||= '127.0.0.1'
PORT ||= 4001

OPTS[:connection] = {
  :account => ACCOUNT, # Your IB PAPER ACCOUNT, tests will only run against it
  :host => HOST, #       Where your TWS/gateway is located, likely '127.0.0.1'
  :port => PORT, #       4001 for Gateway, 7496 for TWS GUI
  :client_id => 1111, #  Client id that identifies the test suit
  :reuters => true #     Subscription to Reuters data enabled ?
}

RSpec.configure do |config|

  puts "Running specs with OPTS:"
  pp OPTS

  # config.filter = { :focus => true }
  # config.include(UserExampleHelpers)
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr

  config.exclusion_filter = {
    :if => proc do |condition|
      t = Time.now.utc
      case condition # NB: excludes if condition is false!
      when :us_trading_hours
        # 09:30 - 16:00 (ET) Mon-Fri 14:30 - 21:00 (UTC)
        !(t.wday >= 1 && t.wday <= 5 && t.hour >= 15 && t.hour <= 21)
      when :forex_trading_hours
        # 17:15 - 17:00 (ET) Sunday-Friday Forex  22:15 - 22:00 (UTC)
        !(t.wday > 0 && t.wday < 5 || t.wday == 5 && t.hour < 22)
      end
    end,

    :db => proc { |condition| IB.db_backed? != condition }, # true/false

    :rails => proc { |condition| IB.rails? != condition }, # false or "Dummy"/"Combustion"

    :reuters => proc { |condition| !OPTS[:connection][:reuters] == condition }, # true/false
  }

  if OPTS[:db]
    require 'database_cleaner'

    config.before(:suite) do
      DatabaseCleaner.strategy = :truncation
      DatabaseCleaner.clean
    end

    config.after(:suite) do
      DatabaseCleaner.clean
    end
  end

  if OPTS[:rails]
    config.include IB::Engine.routes.url_helpers,
      :example_group => {:file_path => /\brails_spec\//}

    config.include Capybara::DSL,
      :example_group => { :file_path => /\brails_spec\//}
  end
end
