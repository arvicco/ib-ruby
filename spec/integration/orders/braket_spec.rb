require 'order_helper'

describe 'Braket Orders', :connected => true, :integration => true do

  before(:all) do
    verify_account
  end

  context "Braket Orders (with profit-taking/stoplimit attached)" do

    before(:all) do
      @ib = IB::Connection.new OPTS[:connection].merge(:logger => mock_logger)
      @ib.wait_for :NextValidId
      @ib.clear_received # to avoid conflict with pre-existing Orders

      @local_id = @ib.next_local_id
      @contract = IB::Symbols::Stocks[:ibm]

      # This is a main order
      @order = IB::Order.new(:total_quantity => 100,
                             :limit_price => 125,
                             :action => 'BUY',
                             :order_type => 'LMT',
                             :order_ref => 'main',
                             :transmit => false)

      # This is an attached stop-loss order
      @stop_order = IB::Order.new(:total_quantity => 100,
                             :aux_price => 123,
                             :action => 'SELL',
                             :order_type => 'STP',
                             :parent_id => @local_id, # of the main order
                             :order_ref => 'stop-loss',
                             :transmit => false)

     # This is an attached take-profit order
      @takeprofit_order = IB::Order.new(:total_quantity => 100,
                             :limit_price => 137,
                             :aux_price => 135,
                             :action => 'SELL',
                             :order_type => 'STPLMT',
                             :parent_id => @local_id, # of the main order
                             :order_ref => 'take-profit',
                             :transmit => true)

      # First, we place parent and attached orders with (transmit=false)
      @ib.place_order @order, @contract
      @ib.place_order @stop_order, @contract

      # And wait couple of seconds to make sure gateway has time to process
      @ib.wait_for 2 # secs
    end

    after(:all) { close_connection }

    it 'does not transmit braket before last one is placed' do
      @ib.received[:OpenOrder].should have_exactly(0).order_message
      @ib.received[:OrderStatus].should have_exactly(0).status_message
    end


    context 'When last braket order is placed' do
      before(:all) do
        # Now, we place last attached order with (transmit=true)
        @ib.place_order @takeprofit_order, @contract

        @ib.wait_for [:OpenOrder, 3], [:OrderStatus, 3], 3
      end


      it 'does transmit all connected braket orders' do
        @ib.received[:OpenOrder].should have_at_least(3).order_message
        @ib.received[:OrderStatus].should have_at_least(3).status_message
      end
    end

    context 'When original Order cancels' do
      before(:all) do
        @ib.cancel_order @local_id

        @ib.wait_for 2 #[:OrderStatus, 3], 3
        @ib.clear_received # make sure old order status messages are disposed of
      end

      it 'attached braket orders are cancelled implicitly' do
        @ib.send_message :RequestOpenOrders
        @ib.wait_for :OpenOrderEnd
        @ib.received[:OpenOrder].should have_exactly(0).order_message
        @ib.received[:OrderStatus].should have_exactly(0).status_message
      end
    end
  end
end

__END__
## This is a Java braket order example offered by API support team
## This spec is (roughly) based upon this example
#
# Contract contract = new Contract();
# contract.m_symbol = "IBM";
# contract.m_secType = "STK";
# contract.m_exchange = "SMART";
# contract.m_currency = "USD";
#
# Order parentOrder = new Order();
# parentOrder.m_action = "BUY";
# parentOrder.m_totalQuantity = 100;
# parentOrder.m_orderType = "LMT";
# parentOrder.m_lmtPrice = 125.00;
# parentOrder.m_orderRef = "Parent";
# parentOrder.m_transmit = false;
#
# Order firstChildOrder = new Order();
# firstChildOrder.m_action = "SELL";
# firstChildOrder.m_totalQuantity = 100;
# firstChildOrder.m_orderType = "STP";
# firstChildOrder.m_auxPrice = 127.00;
# firstChildOrder.m_parentId = globalOrderId;
# firstChildOrder.m_transmit = false;
#
# Order secondChildOrder = new Order();
# secondChildOrder.m_action = "BUY";
# secondChildOrder.m_totalQuantity = 100;
# secondChildOrder.m_orderType = "STPLMT";
# secondChildOrder.m_lmtPrice = 125.00;
# secondChildOrder.m_auxPrice = 137.00;
# secondChildOrder.m_parentId = globalOrderId;
# secondChildOrder.m_transmit = true;
#
# m_client.placeOrder(globalOrderId++, contract, parentOrder);
# m_client.placeOrder(globalOrderId++, contract, firstChildOrder);
# m_client.placeOrder(globalOrderId++, contract, secondChildOrder);
