require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/fixtures/classes'

describe "Bignum#coerce when given a Fixnum or Bignum" do
  it "returns an Array containing the given argument and self" do
    a = BignumHelper.sbm
    a.coerce(2).should == [2, a]
    
    b = BignumHelper.sbm(701)
    a.coerce(b).should == [b, a]
  end
end

describe "Bignum#coerce" do
  it "raises a TypeError when given a non Fixnum/Bignum" do
    a = BignumHelper.sbm

    lambda { a.coerce(nil) }.should raise_error(TypeError)
    lambda { a.coerce(mock('str')) }.should raise_error(TypeError)
    lambda { a.coerce(1..4) }.should raise_error(TypeError)
    lambda { a.coerce(:test) }.should raise_error(TypeError)

    compliant_on :ruby do
      lambda { a.coerce(12.3) }.should raise_error(TypeError)
      lambda { a.coerce("123") }.should raise_error(TypeError)
    end
  end
end