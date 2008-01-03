require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/fixtures/classes'

describe "Struct[]" do
  it "is a synonym for new" do
    Struct::Ruby['2.0', 'i686'].class.should == Struct::Ruby
  end
end

describe "Struct#[]" do
  it "returns the attribute referenced" do
    car = Struct::Car.new('Ford', 'Ranger')
    car['make'].should == 'Ford'
    car['model'].should == 'Ranger'
    car[:make].should == 'Ford'
    car[:model].should == 'Ranger'
    car[0].should == 'Ford'
    car[1].should == 'Ranger'
  end

  it "fails when it does not know about the requested attribute" do
    car = Struct::Car.new('Ford', 'Ranger')
    lambda { car[5]        }.should raise_error(IndexError)
    lambda { car[:body]    }.should raise_error(NameError)
    lambda { car['wheels'] }.should raise_error(NameError)
  end

  it "fails if passed too many arguments" do
    car = Struct::Car.new('Ford', 'Ranger')
    lambda { car[:make, :model] }.should raise_error(ArgumentError)
  end

  it "fails if not passed a string, symbol, or integer" do
    car = Struct::Car.new('Ford', 'Ranger')
    lambda { car[Time.now]               }.should raise_error(TypeError)
    lambda { car[ { :name => 'chris' } ] }.should raise_error(TypeError)
    lambda { car[ ['chris', 'evan'] ]    }.should raise_error(TypeError)
    lambda { car[ Class ]                }.should raise_error(TypeError)
  end
end