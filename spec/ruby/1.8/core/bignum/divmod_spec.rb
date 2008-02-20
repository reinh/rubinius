require File.dirname(__FILE__) + '/../../spec_helper'

describe "Bignum#divmod" do
  before(:each) do
    @bignum = bignum_value(55)
  end
  
  it "returns an Array containing quotient and modulus obtained from dividing self by the given argument" do
    @bignum.divmod(4).should == [2305843009213693965, 3]
    @bignum.divmod(13).should == [709490156681136604, 11]

    @bignum.divmod(4.0).should == [2305843009213693952, 0.0]
    @bignum.divmod(13.0).should == [709490156681136640, 8.0]

    @bignum.divmod(2.0).should == [4611686018427387904, 0.0]
    @bignum.divmod(bignum_value).should == [1, 55]
    (-(10**50)).divmod(-(10**40 + 1)).should == [9999999999, -9999999999999999999999999999990000000001]
    (10**50).divmod(10**40 + 1).should == [9999999999, 9999999999999999999999999999990000000001]
  end

  # Based on MRI's test/test_integer.rb (test_divmod),
  # MRI maintains the following property:
  # if q, r = a.divmod(b) ==>
  # assert(0 < b ? (0 <= r && r < b) : (b < r && r <= 0))
  # So, r is always between 0 and b.
  compliant_on :ruby, :jruby do
    it "correctly handles negative values for x or y in x.divmod(y)" do
      (-10**50).divmod(10**40 + 1).should == [-10000000000, 10000000000]
      (10**50).divmod(-(10**40 + 1)).should == [-10000000000, -10000000000]
    end
  end

  # see http://rubyforge.org/tracker/index.php?func=detail&aid=16988&group_id=426&atid=1698
  deviates_on :rubinius do
    it "correctly handles negative values for x or y in x.divmod(y)" do
      (-10**50).divmod(10**40 + 1).should == [-9999999999, -9999999999999999999999999999990000000001]
      (10**50).divmod(-(10**40 + 1)).should == [-9999999999, 9999999999999999999999999999990000000001]
    end
  end
  
  it "raises a ZeroDivisionError when the given argument is 0" do
    lambda { @bignum.divmod(0) }.should raise_error(ZeroDivisionError)
    lambda { (-@bignum).divmod(0) }.should raise_error(ZeroDivisionError)
  end
  
  it "raises a FloatDomainError when the given argument is 0 and a Float" do
    lambda { @bignum.divmod(0.0) }.should raise_error(FloatDomainError, "NaN")
    lambda { (-@bignum).divmod(0.0) }.should raise_error(FloatDomainError, "NaN")
  end

  it "raises a TypeError when given a non-Integer" do
    lambda {
      (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
      @bignum.divmod(obj)
    }.should raise_error(TypeError)
    lambda { @bignum.divmod("10") }.should raise_error(TypeError)
    lambda { @bignum.divmod(:symbol) }.should raise_error(TypeError)
  end
end
