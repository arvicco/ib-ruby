require 'integration_helper'

# Most Order placement specs implicitly depend on Gateway/TWS state,
# assuming no orders are hanging around from other specs or otherwise
# We need to have a clean slate before each spec run
def cancel_orders
    @ib = IB::Connection.new OPTS[:connection].merge(:logger => mock_logger)
    @ib.wait_for :OpenOrderEnd
    @ib.send_message :RequestGlobalCancel
    @ib.send_message :RequestAllOpenOrders
    @ib.wait_for :OpenOrderEnd
    close_connection
end

# Define butterfly (combo contract that displays some tricky order-related bugs)
def butterfly symbol, expiry, right, *strikes
  raise 'Unable to create butterfly, no connection' unless @ib && @ib.connected?

  legs = strikes.zip([1, -2, 1]).map do |strike, weight|

    # Create contract
    contract = IB::Option.new :symbol => symbol,
                              :expiry => expiry,
                              :right => right,
                              :strike => strike

    # Find out contract's con_id
    @ib.clear_received :ContractData, :ContractDataEnd
    @ib.send_message :RequestContractData, :id => strike, :contract => contract
    @ib.wait_for :ContractDataEnd, 3
    con_id = @ib.received[:ContractData].last.contract.con_id

    # Create Comboleg from con_id and weight
    IB::ComboLeg.new :con_id => con_id, :weight => weight
  end

  # Return butterfly Combo
  IB::Bag.new :symbol => symbol,
              :currency => "USD", # Only US options in combo Contracts
              :exchange => "SMART",
              :legs => legs
end

shared_examples_for 'Placed Order' do
  context "Placing" do
    after(:all) { clean_connection } # Clear logs and message collector

    it 'sets placement-related properties' do
      @order.placed_at.should be_a Time
      @order.modified_at.should be_a Time
      @order.placed_at.should == @order.modified_at
      @order.local_id.should be_an Integer
      @order.local_id.should == @local_id_before
    end

    it 'changes client`s next_local_id' do
      @local_id_placed.should == @local_id_before
      @ib.next_local_id.should be >= @local_id_before
    end

    it 'receives all appropriate response messages' do
      @ib.received[:OpenOrder].should have_at_least(1).order_message
      @ib.received[:OrderStatus].should have_at_least(1).status_message
    end

    it 'receives confirmation of Order submission' do
      order_should_be /Submit/ # (Pre)Submitted
      status_should_be /Submit/
      order_should_be( /Submit/, @attached_order) if @attached_order
    end
  end # Placing

  context "Retrieving placed" do
    before(:all) do
      @ib.send_message :RequestOpenOrders
      @ib.wait_for :OpenOrderEnd
    end

    after(:all) { clean_connection } # Clear logs and message collector

    it 'does not increase client`s next_local_id further' do
      @ib.next_local_id.should == @local_id_after
    end

    it 'receives all appropriate response messages' do
      @ib.received[:OpenOrder].should have_at_least(1).order_message
      @ib.received[:OrderStatus].should have_at_least(1).status_message
      @ib.received[:OpenOrderEnd].should have_exactly(1).order_end_message
    end

    it 'receives OpenOrder and OrderStatus for placed order(s)' do
      order_should_be /Submitted/
      status_should_be /Submitted/
      order_should_be( /Submit/, @attached_order) if @attached_order
    end
  end # Retrieving

  context "Modifying Order" do
    before(:all) do
      # Modify main order
      @order.total_quantity *= 2
      @order.limit_price += 0.05
      @order.transmit = true
      @order.tif = 'GTC'
      @ib.modify_order @order, @contract

      # Modify attached order, if any
      if @attached_order
        @attached_order.limit_price += 0.05 unless @attached_order.order_type == :stop
        @attached_order.total_quantity *= 2
        @attached_order.tif = 'GTC'
        @ib.modify_order @attached_order, @contract
      end
      @ib.send_message :RequestOpenOrders
      @ib.wait_for :OpenOrderEnd, 5 #sec
    end

    after(:all) { clean_connection } # Clear logs and message collector

    it 'sets placement-related properties' do
      @order.modified_at.should be_a Time
      @order.placed_at.should_not == @order.modified_at
    end

    it 'does not increase client`s or order`s local_id any more' do
      @order.local_id.should == @local_id_before
      @ib.next_local_id.should == @local_id_after
    end

    it 'receives all appropriate response messages' do
      @ib.received[:OpenOrder].should have_at_least(1).order_message
      @ib.received[:OrderStatus].should have_at_least(1).status_message
      @ib.received[:OpenOrderEnd].should have_exactly(1).order_end_message
    end

    it 'modifies the placed order(s)' do
      @contract.should == @ib.received[:OpenOrder].first.contract
      order_should_be /Submit/
      status_should_be /Submit/
      order_should_be( /Submit/, @attached_order) if @attached_order
    end
  end # Modifying

  context "Cancelling placed order" do
    before(:all) do
      @ib.cancel_order @local_id_placed
      @ib.wait_for [:OpenOrder, 2], :Alert, 3
    end

    after(:all) { clean_connection } # Clear logs and message collector

    it 'does not increase client`s next_local_id further' do
      @ib.next_local_id.should == @local_id_after
    end

    # it 'only receives OpenOrder message with (Pending)Cancel',
    #   :pending => 'Receives OrderState: PreSubmitted from previous context' do
    #   if @ib.received? :OpenOrder
    #     order_should_be /Cancel/
    #   end
    # end

    it 'receives all appropriate response messages' do
      @ib.received[:OrderStatus].should have_at_least(1).status_message
      @ib.received[:Alert].should have_at_least(1).alert_message
    end

    it 'receives cancellation Order Status' do
      status_should_be /Cancel/ # Cancelled / PendingCancel
      status_should_be( /Cancel/, @attached_order) if @attached_order
        # if contract_type == :butterfly && @attached_order.tif == :good_till_cancelled
        #   pending 'API Bug: Attached GTC orders not working for butterflies!'
        #   # But you may set attached DAY order and then modify it to GTC ;)
        # end
    end

    it 'receives Order cancelled Alert' do
      alert = @ib.received[:Alert].first
      alert.should be_an IB::Messages::Incoming::Alert
      alert.message.should =~ /Order Canceled - reason:/
    end
  end # Cancelling
end

### Helpers for placing and verifying orders

def place_order contract, opts = {}
  @contract = contract
  @order = IB::Order.new({:total_quantity => 100,
                          :limit_price => 9.13,
                          :action => 'BUY',
                          :order_type => 'LMT'}.merge(opts))
  @local_id_before = @ib.next_local_id
  @local_id_placed = @ib.place_order @order, @contract
  @local_id_after = @ib.next_local_id
end

def status_should_be status, order=@order
  msg = find_order_message :OrderStatus, status, order
  msg.should_not be_nil
  msg.should be_an IB::Messages::Incoming::OrderStatus
  order_state = msg.order_state
  order_state.local_id.should == order.local_id
  order_state.perm_id.should be_an Integer
  order_state.client_id.should == OPTS[:connection][:client_id]
  order_state.parent_id.should == 0 unless @attached_order
  order_state.why_held.should == ''

  if @contract == IB::Symbols::Forex[:eurusd]
    # We know that this order filled for sure
    order_state.filled.should == 20000
    order_state.remaining.should == 0
    order_state.average_fill_price.should be > 1
    order_state.average_fill_price.should be < 2
    order_state.last_fill_price.should == order_state.average_fill_price
  else
    order_state.filled.should == 0
    order_state.remaining.should == order.total_quantity
    order_state.average_fill_price.should == 0
    order_state.last_fill_price.should == 0
  end
end

def order_should_be status, order=@order
  msg = find_order_message :OpenOrder, status, order
  msg.should_not be_nil
  msg.should be_an IB::Messages::Incoming::OpenOrder
  # pp order, msg.order
  msg.order.should == order
  msg.contract.should == @contract
end

def find_order_message type, status, order=@order
  @ib.received[type].find do |msg|
    msg.local_id == order.local_id &&
      status.is_a?(Regexp) ? msg.status =~ status : msg.status == status
  end
end
