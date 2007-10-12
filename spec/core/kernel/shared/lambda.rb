@kernel_lambda = shared "Kernel#lambda" do |cmd|
  describe "Kernel.#{cmd}" do
    it "should return a Proc object" do
      send(cmd) { true }.kind_of?(Proc).should == true
    end
  
    it "raises an ArgumentError when no block is given" do
      should_raise(ArgumentError) { send(cmd) }
    end
  
    it "raises an ArgumentError when given to many arguments" do
      should_raise(ArgumentError) { send(cmd) { |a, b| a + b}.call(1,2,5).should == 3 }
    end
  
    it "returns from block into caller block" do
      # More info in the pickaxe book pg. 359
      def some_method(cmd)
        p = send(cmd) { return 99 }
        res = p.call
        "returned #{res}"
      end
 
      # Have to pass in the cmd errors otherwise
      some_method(cmd).should == "returned 99"
  
      def some_method2(&b) b end
      a_proc = send(cmd) { return true }
      res = some_method2(&a_proc)
  
      res.call.should == true
    end
  end
end