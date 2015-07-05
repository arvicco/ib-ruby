# Option contracts definitions.
# TODO: add next_expiry and other convenience from Futures module.
module IB
  module Symbols
    module Options
      extend Symbols

      def self.contracts
        @contracts ||= {
          :wfc50 => IB::Option.new(:symbol => "WFC",
                                   :expiry => "201601",
                                   :right => "CALL",
                                   :strike => 50.0,
                                   :description => "Wells Fargo 50 Call 2016-01"),
          :aapl100 => IB::Option.new(:symbol => "AAPL",
                                     :expiry => "201601",
                                     :right => "CALL",
                                     :strike => 100,
                                     :description => "Apple 100 Call 2016-01"),
          # Doesn't seem to work currently                           
          :z50 => IB::Option.new(:symbol => "Z",
                                 :exchange => "LIFFE",
                                 :expiry => "201601",
                                 :right => "CALL",
                                 :strike => 50.0,
                                 :description => " FTSE-100 index 50 Call 2016-01"),
          :spy75 => IB::Option.new(:symbol => 'SPY',
                                   :expiry => "201601",
                                   :right => "P",
                                   :currency => "USD",
                                   :strike => 75.0,
                                   :description => "SPY 75.0 Put 2016-01"),
          :spy100 => IB::Option.new(:osi => 'SPY 160115P00100000'),
          :vxx40 => IB::Option.new(:osi =>  'VXX 160115C00040000'),
        }
      end
    end
  end
end
