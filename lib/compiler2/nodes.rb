class Compiler2
class Node
  Mapping = {}
  
  def self.kind(name=nil)
    return @kind unless name
    Mapping[name] = self
    @kind = name
  end
  
  def self.create(compiler, sexp)
    sexp.shift
    
    node = new(compiler)
    args = node.consume(sexp)

    begin
      if node.respond_to? :normalize
        node = node.normalize(*args)
      else
        node.args(*args)
      end
    rescue ArgumentError => e
      raise ArgumentError, "#{kind} (#{self}) takes #{args.size} argument(s): passed #{args.inspect} (#{e.message})", e.context
    end
    
    return node
  end
  
  def initialize(compiler)
    @compiler = compiler
  end
  
  def convert(x)
    @compiler.convert_sexp(x)
  end
  
  def consume(sexp)
    # This lets nil come back from convert_sexp which means
    # leave it out of the stream. This is primarily so that
    # expressions can be optimized away and wont be seen at
    # all in the output stream.
    out = []
    sexp.each do |x|        
      if x.kind_of? Array
        v = @compiler.convert_sexp(x)
        out << v unless v.nil?
      else
        out << x
      end
    end
    
    return out
  end
  
  def args
  end
  
  def get(tag)
    @compiler.get(tag)
  end
  
  def set(tag, val=true, &b)
    @compiler.set(tag, val, &b)
  end
  
  def inspect
    kind = self.class.kind
    if kind
      prefix = "Compiler2:#{self.class.kind}"
    else
      prefix = self.class.name
    end
    prefix
    
    super(prefix)
  end
  
  def is?(clas)
    self.kind_of?(clas)
  end
  
  # Start of Node subclasses
  
  class ClosedScope < Node
    def initialize(comp)
      super(comp)
      
      @use_eval = false
      @alloca = 0
      @slot = 0
      @top_scope = create_scope()
      @block_scope = []
      @all_scopes = [@top_scope]
      @ivar_as_slot = {}
    end
    
    def create_scope
      Compiler2::LocalScope.new(self)
    end
    
    attr_accessor :use_eval
    
    def locals
      @top_scope.size
    end
    
    def name
      nil
    end
    
    def consume(sexp)
      set(:scope => self, :visibility => :public, :iter => false) do
        out = convert(sexp[0])
        @all_scopes.each do |scope|
          scope.formalize!
        end
        out
      end
    end
    
    def depth
      @block_scope.size
    end
    
    def new_block_scope
      begin
        scope = create_scope()
        @block_scope << scope
        @all_scopes << scope
        yield
      ensure
        @block_scope.pop
      end
      
      return scope.size
    end
    
    def find_local(name, in_block=false)
      # If the caller is not in a block, things can only
      # be in the top_context. Easy enough, return out of the Hash 
      # (which might created in for us automatically)
      return [@top_scope[name], nil] unless in_block
      
      # They're asking from inside a block, look in the current
      # block scopes as well as top_scope
      
      if @block_scope.empty?
        raise Error, "You can't be in a block, there are no block scopes"
      end
            
      lcl = nil   
      depth = nil
      dep = 0
      
      @block_scope.reverse_each do |scope|
        if scope.key?(name)
          depth = dep
          lcl = scope[name]
          break
        end
        dep += 1
      end
      
      # Not found in an outstanding block scope, look in the 
      # top context.
      unless lcl
        if @top_scope.key?(name)
          lcl = @top_scope[name]
        else
          # This not found. create it.
          in_scope = @block_scope.last
          idx = in_scope.size
          lcl = in_scope[name]
          lcl.created_in_block!(idx)
          depth = 0
        end
      end
      
      lcl.access_in_block!
      
      return [lcl, depth]
    end
    
    def find_ivar_index(name)
      @ivar_as_slot[name]
    end
    
    def add_ivar_as_slot(name, slot)
      @ivar_as_slot["@#{name}".to_sym] = slot
    end
    
    def allocate_stack
      return nil if @use_eval
      # This is correct. the first one is 1, not 0.
      @alloca += 1
    end
    
    def allocate_slot
      i = @slot
      @slot += 1
      return i
    end
  end
    
  class Snippit < ClosedScope
    kind :snippit
    
    def consume(sexp)
      set(:family, self) do
        super(sexp)
      end
    end
    
    def args(body)
      @body = body
    end
    
    attr_accessor :body
  end
  
  class Script < ClosedScope
    kind :script
    
    def args(body)
      @body = body
    end

    attr_accessor :body
    
    def name
      :__script__
    end
  end
  
  class Newline < Node
    kind :newline
    
    
    def consume(sexp)
      @compiler.set_position sexp[1], sexp[0]
      super sexp
    end
    
    def args(line, file, child=nil)
      @line, @file, @child = line, file, child
    end
    
    attr_accessor :line, :file, :child
    
    def is?(cls)
      @child.kind_of? cls
    end
  end
  
  class True < Node
    kind :true
  end
  
  class False < Node
    kind :false
  end
  
  class Nil < Node
    kind :nil
  end
  
  class Self < Node
    kind :self
  end
  
  class And < Node
    kind :and
    
    def args(left, right)
      @left, @right = left, right
    end
    
    attr_accessor :left, :right
  end
  
  class Or < And
    kind :or
  end
  
  class Not < Node
    kind :not
    
    def args(child)
      @child = child
    end
    
    attr_accessor :child
  end
  
  class Negate < Node
    kind :negate
    
    def args(child)
      @child = child
    end
    
    attr_accessor :child
  end
  
  class NumberLiteral < Node
    kind :fixnum
    
    def args(value)
      @value = value
    end
    
    attr_accessor :value
  end
  
  class Literal < Node
    kind :lit
    
    def normalize(value)
      @value = value
      
      case value
      when Fixnum
        nd = NumberLiteral.new(@compiler)
        nd.args(value)
        return nd
      when Regexp
        nd = RegexLiteral.new(@compiler)
        nd.args(value.source, value.options)
        return nd
      end
      
      return self
    end
    
    attr_accessor :value
  end
  
  class RegexLiteral < Node
    kind :regex
    
    def args(source, options)
      @source, @options = source, options
    end
    
    attr_accessor :source, :options
  end
  
  class StringLiteral < Node
    kind :str
    
    def args(str)
      @string = str
    end
    
    attr_accessor :string
  end
  
  
  class DynamicString < StringLiteral
    kind :dstr
    
    def args(str, *body)
      @string = str
      @body = body
    end
    
    attr_accessor :body
  end
  
  class DynamicRegex < DynamicString
    kind :dregx
  end
  
  class DynamicOnceRegex < DynamicRegex
    kind :dregx_once
  end
  
  class Match2 < Node
    kind :match2
    
    def args(pattern, target)
      @pattern, @target = pattern, target
    end
    
    attr_accessor :pattern, :target
  end
  
  class Match3 < Node
    kind :match3
    
    def args(pattern, target)
      @target, @pattern = target, pattern
    end
    
    attr_accessor :target, :pattern
  end
  
  class BackRef < Node
    kind :back_ref
    
    def args(kind)
      @kind = kind.chr.to_sym
    end
    
    attr_accessor :kind
  end
  
  class NthRef < Node
    kind :nth_ref
    
    def args(which)
      @which = which
    end
    
    attr_accessor :which
  end
  
  class If < Node
    kind :if
    
    def args(cond, thn, els)
      @condition, @then, @else = cond, thn, els
    end
    
    attr_accessor :condition, :then, :else
  end
    
  class While < Node
    kind :while
    
    def args(cond, body, check_first=true)
      @condition, @body, @check_first = cond, body, check_first
    end
    
    attr_accessor :condition, :body, :check_first
  end
  
  class Until < While
    kind :until
  end
  
  class Block < Node
    kind :block
    
    def args(*body)
      @body = body
    end
    
    attr_accessor :body
  end
  
  class Scope < Node
    kind :scope
    
    def consume(sexp)
      if sexp.size == 1 or sexp[0].nil?
        return [nil, nil]
      end
      
      # Handle def self.foo; end, which unlike def foo; end does not generate a block
      if sexp[0].first == :args
        sexp[0] = [:block, sexp[0], [:nil]]
      end

      sexp[0] = convert(sexp[0])
      return sexp
    end
    
    def args(block, locals)
      @block, @locals = block, locals
    end
    
    attr_accessor :block, :locals
  end
  
  class Arguments < Node
    kind :args
    
    # [[:obj], [], nil, nil]
    # required, optional, splat, defaults
    def consume(sexp)
      
      if sexp.empty?
        return [[], [], nil, nil]
      end
      
      # Strip the parser calculated index of splat
      if sexp[2] and sexp[2].size == 2
        sexp[2] = sexp[2].first
      end
      
      defaults = sexp[3]
      
      if defaults
        defaults.shift
        i = 0
        defaults.map! do |node|
          # HACK: Fix parse_tree bug when an optional arg has a default value
          # that is an :iter. For example, the following:
          #  def foo(output = 1, b = lambda {|n| output * n})
          # generates a sexp where the optional args are [:output, :n], rather
          # than [:output, :b]. To fix this, we pick up the name of the :lasgn,
          # in the defaults, and set the corresponding optional arg if the
          # :lasgn is an :iter.
          if node[3].first == :iter
            name = node[1]
            sexp[1][i] = name
          end
          i += 1

          convert(node)
        end
        
        sexp[3] = defaults
      end
      
      sexp
    end
    
    def args(req, optional, splat, defaults)
      @block_arg = nil
      @required, @optional, @splat, @defaults = req, optional, splat, defaults
      populate
    end
    
    attr_accessor :required, :optional, :splat, :defaults, :block_arg
    
    def arity
      if !@optional.empty? or @splat
        return -(@required.size + 1)
      end
      
      return @required.size
    end
    
    def populate
      i = 0
      scope = get(:scope)
      
      @required.map! do |var|
        var, depth = scope.find_local(var)
        var.argument!(i)
        i += 1
        var
      end
      
      @optional.map! do |var|
        var, depth = scope.find_local(var)
        var.argument!(i, true)
        i += 1
        var
      end
      
      if @splat
        var, depth = scope.find_local(splat)
        var.argument!(i, true)
        @splat = var
      end
      
      @mapped_defaults = {}

      if @defaults
        @defaults.each do |x|
          @mapped_defaults[x.name] = x
        end
      end
      
    end
  end
  
  class Undef < Node
    kind :undef
    
    def args(name)
      @name = name
      scope = get(:scope)
      if scope.is? Node::Class or scope.is? Node::Module
        @in_module = true
      else
        @in_module = false
      end
    end
    
    attr_accessor :name, :in_module
  end
  
  class Break < Node
    kind :break
    def args(value=nil)
      @value = value
      @in_block = get(:iter)
    end
    
    attr_accessor :value, :in_block
  end
  
  class Redo < Break
    kind :redo
  end
  
  class Next < Break
    kind :next
  end
  
  class Retry < Break
    kind :retry
  end
  
  class When < Node
    kind :when
    
    def args(cond, body = nil)
      @body = body
      @conditions = []
      @splat = nil

      if cond.is? ArrayLiteral      
        cond.body.each do |c|
          # Inner when means splat.
          if c.is? Compiler2::Node::When
            if c.splat
              @splat = c.splat
            else
              @splat = c.conditions
            end
          else
            @conditions << c
          end
        end
      else
        @splat = cond
      end
    end
    
    attr_reader :body, :conditions, :splat
  end
  
  class Case < Node
    kind :case
    
    def consume(sexp)
      sexp[1].map! do |w|
        convert(w)
      end
      [convert(sexp[0]), sexp[1], convert(sexp[2])]
    end
    
    def args(recv, whens, els)
      @receiver, @whens, @else = recv, whens, els
    end
    
    def has_receiver?
      true
    end
    
    attr_accessor :receiver, :whens, :else
  end
  
  # ManyIf represents a case statement with no receiver, i.e.
  #   case
  #     when foo: bar
  #   end
  class ManyIf < Case
    kind :many_if
    
    # :many_if contains an array of whens and an else
    # the whens are in turn an array of condition expressions,
    # followed by a body
    def consume(sexp)
      whens = sexp[0]
      whens.map! do |w|
        w.unshift :when
        convert(w)
      end
      [whens, convert(sexp[1])]
    end
    
    def args(whens, els)
      @whens = whens
      @else = els
    end
    
    def has_receiver?
      false
    end

    attr_accessor :whens, :else
  end
  
  class LocalVariable < Node
    def args(name)
      scope = get(:scope)
      
      if get(:iter)
        @variable, @depth = scope.find_local name, true
      else
        @variable, @depth = scope.find_local name
      end
      
      @name = name
    end
    
    def from_variable(var)
      @variable = var
      @depth = nil
      @name = var.name
    end
    
  end

  class LocalAssignment < LocalVariable
    kind :lasgn
    
    def args(name, idx, val=nil)
      # val will be nil if this is e.g. an lasgn inside an masgn
      @value = val
      super(name)
      
      @variable.assigned!
    end
    
    attr_accessor :name, :value, :variable
    
    def from_variable(var, value=nil)
      super(var)
      
      @value = value
    end
  end
  
  class LocalAccess < LocalVariable
    kind :lvar
    
    def args(name, idx)
      @name = name
      super(name)
    end
    
    attr_accessor :name    
  end
    
  class SValue < Node
    kind :svalue
    
    def args(child)
      @child = child
    end
    
    attr_accessor :child
  end
    
  class OpAssignOr < Node
    kind :op_asgn_or
    
    def args(left, right)
      @left, @right = left, right
    end
    
    attr_accessor :left, :right
  end
  
  class OpAssignAnd < OpAssignOr
    kind :op_asgn_and
  end
  
  class OpAssign1 < Node
    kind :op_asgn1

    def consume(sexp)
      # Value to be op-assigned is always first element of value
      sexp[2].shift # Discard :array token
      val = convert(sexp[2].shift)
      # Remaining elements in value are index args excluding final nil marker
      idx = []
      while sexp[2].size > 1 do
        idx << convert(sexp[2].shift)
      end
      [convert(sexp[0]), sexp[1], idx, val]
    end

    def args(obj, kind, index, value)
      @object, @kind, @index, @value = obj, kind, index, value
    end
    
    attr_accessor :object, :kind, :value, :index
  end
  
  class OpAssign2 < Node
    kind :op_asgn2
    
    def args(obj, method, kind, assign, value)
      @object, @method, @kind, @value = obj, method, kind, value
      str = assign.to_s
      if str[-1] == ?=
        @assign = assign
      else
        str << "="
        @assign = str.to_sym
      end
    end
    
    attr_accessor :object, :method, :kind, :assign, :value
  end
    
  class ArrayLiteral < Node
    kind :array
    
    def args(*body)
      @body = body
    end
    
    attr_accessor :body
  end
  
  class EmptyArray < Node
    kind :zarray
  end
    
  class HashLiteral < Node
    kind :hash
    
    def args(*body)
      @body = body
    end
    
    attr_accessor :body
  end
  
  class ImplicitHash < HashLiteral
    kind :ihash
  end
  
  class DynamicArguments < Node
  end
  
  class Splat < DynamicArguments
    kind :splat
    
    def args(child)
      @child = child
    end
    
    attr_accessor :child
    
  end
  
  class ConcatArgs < DynamicArguments
    kind :argscat
    
    def args(rest, array)
      @array = array
      
      if rest.kind_of? Array      # When does this happen?
        @rest = rest
      else
        @rest = rest.body
      end
    end
    
    attr_accessor :array, :rest
  end
  
  class PushArgs < DynamicArguments
    kind :argspush
    
    def args(array, item)
      @item = item
      unless array.is? Splat
        raise Error, "Unknown form of argspush: #{array.class}"
      end
      
      @array = array.child
    end
    
    attr_accessor :array, :item
  end
  
  class AccessSlot < Node
    def args(idx)
      @index = idx
    end
    
    attr_reader :index
  end
  
  class SetSlot < Node
    def args(idx, val)
      @index, @value = idx, val
    end
    
    attr_reader :index, :value
  end
  
  class IVar < Node
    kind :ivar
    
    def normalize(name)
      fam = get(:family)
      if fam and idx = fam.find_ivar_index(name)
        ac = AccessSlot.new @compiler
        ac.args(idx)
        return ac
      end
      
      @name = name
      return self
    end
    
    attr_accessor :name
    
  end
  
  class IVarAssign < Node
    kind :iasgn
    
    def normalize(name, val=nil)
      fam = get(:family)
      if fam and idx = fam.find_ivar_index(name)
        ac = SetSlot.new @compiler
        ac.args(idx, val)
        return ac
      end
      
      @value = val
      @name = name
      return self
    end
        
    attr_accessor :name, :value
  end
  
  class GVar < Node
    kind :gvar
    
    def args(name)
      @name = name
    end
    
    attr_accessor :name
  end
  
  class GVarAssign < Node
    kind :gasgn
    
    def args(name, value=nil)
      @name, @value = name, value
    end
    
    attr_accessor :name, :value
  end
  
  class ConstFind < Node
    kind :const
    
    def args(name)
      @name = name
    end
    
    attr_accessor :name
  end
  
  class ConstAccess < Node
    kind :colon2
    
    def args(parent, name)
      @parent, @name = parent, name
    end
    
    attr_accessor :parent, :name
    
    def normalize(one, two=nil)
      if two
        args(one, two)
        node = self
      else
        node = ConstFind.new(@compiler)
        node.args(one)
      end
      
      return node
    end
  end
  
  class ConstAtTop < Node
    kind :colon3
    
    def args(name)
      @name = name
    end
    
    attr_accessor :name
  end
  
  class ConstSet < Node
    kind :cdecl
    
    def args(simp, val, complex)
      @from_top = false
      
      @value = val
      if simp
        @parent = nil
        @name = simp
      elsif complex.is? ConstAtTop
        @from_top = true
        @name = complex.name
      else
        @parent = complex.parent
        @name = complex.name
      end
    end
    
    attr_accessor :from_top, :parent, :value, :name
  end
  
  class ToArray < Node
    kind :to_ary
    
    def args(child)
      @child = child
    end
    
    attr_accessor :child
  end
  
  class SClass < ClosedScope
    kind :sclass
    
    def args(obj, body)
      @object, @body = obj, body
    end
    
    def consume(sexp)
      [convert(sexp[0]), super([sexp[1]])]
    end
    
    attr_accessor :object, :body
  end
  
  class Class < ClosedScope
    kind :class
    
    def args(name, parent, sup, body)
      @name, @parent, @superclass, @body = name, parent, sup, body
    end
    
    def consume(sexp)
      name = convert(sexp[0])
      sym = name.name
      
      if name.is? ConstFind
        parent = nil
      else
        parent = name.parent
      end
      
      body = set(:family, self) do
        super([sexp[2]])
      end
            
      [sym, parent, convert(sexp[1]), body]
    end
    
    attr_accessor :name, :parent, :superclass, :body
  end
  
  class Module < ClosedScope
    kind :module
    
    def args(name, parent, body)
      @name, @parent, @body = name, parent, body
    end
    
    def consume(sexp)
      name = convert(sexp[0])
      sym = name.name
      
      if name.is? ConstFind
        parent = nil
      else
        parent = name.parent
      end
      
      [sym, parent, super([sexp[1]])]
    end
    
    attr_accessor :name, :body, :parent
  end
  
  class Begin < Node
    kind :begin
    
    def args(body)
      @body = body
    end
    
    attr_accessor :body
  end
  
  class RescueCondition < Node
    kind :resbody
    
    def args(cond, body, nxt)
      @body, @next = body, nxt
      if cond.nil?
        cf = ConstFind.new(@compiler)
        cf.args :StandardError
        @conditions = [cf]
      elsif cond.is? ArrayLiteral
        @conditions = cond.body
        @splat = nil
      elsif cond.is? Splat
        @conditions = nil
        @splat = cond.child
      elsif cond.is? ConcatArgs
        @conditions = cond.rest
        @splat = cond.array
      else
        raise Error, "Unknown rescue condition form"
      end
    end
    
    attr_accessor :conditions, :splat, :body, :next
  end
  
  class Rescue < Node
    kind :rescue
    
    def args(body, res, els)
      @body, @rescue, @else = body, res, els
    end
    
    def consume(sexp)
      body, res, els = *sexp
      
      if res.nil?
        body = nil
        set(:in_rescue) do
          res = convert(body)
        end
        els = nil
      elsif els.nil?
        if body.first == :resbody
          body = nil
          
          els = convert(res)
          
          set(:in_rescue) do
            res = convert(body)
          end
        else
          body = convert(body)
          set(:in_rescue) do
            res = convert(res)
          end
          els = nil
        end
      else
        body = convert(body)
        set(:in_rescue) do
          res = convert(res)
        end
        els = convert(els)
      end
            
      [body, res, els]
    end
    
    attr_accessor :body, :rescue, :else
  end
  
  class Defined < Node
    kind :defined
    
    def consume(sexp)
      if sexp[0] == :call
        sexp[1] = convert(sexp[1])
      end
      
      sexp      
    end
    
    def args(expr)
      @expression = expr
    end
    
    attr_accessor :expression
  end
  
  class Ensure < Node
    kind :ensure
    
    def consume(sexp)
      opts = {}
      set(:in_ensure, opts) do
        sexp[0] = convert(sexp[0])
      end
      
      # Propagate did_return up to an outer ensure
      if ens = get(:in_ensure)
        ens[:did_return] = opts[:did_return]
        outer = true
      else
        outer = false
      end
      
      [sexp[0], convert(sexp[1]), opts[:did_return], outer]
    end
    
    def args(body, ens, ret, outer)
      @body, @ensure = body, ens
      @did_return = ret
      @outer_ensure = outer
      
      # Handle a 'bug' in parsetree
      if @ensure == [:nil]
        @ensure = nil
      end
    end
    
    attr_accessor :body, :ensure, :did_return, :outer_ensure
  end
  
  class Return < Node
    kind :return
    
    def args(val=nil)
      @value = val
      @in_rescue = get(:in_rescue)
      
      if ens = get(:in_ensure)
        ens[:did_return] = self
        @in_ensure = true
      else
        @in_ensure = false
      end
      
      @in_block = get(:iter)
    end
    
    attr_accessor :value, :in_rescue, :in_ensure, :in_block
  end
  
  class MAsgn < Node
    kind :masgn

    def args(assigns, splat, source=:bogus)
      if source == :bogus  # Only two args supplied, therefore no assigns
        @assigns = nil
        @splat = assigns
        @source = splat
      else
        @assigns, @splat, @source = assigns, splat, source
      end
      
      @in_block = get(:iter_args)
    end
    
    attr_accessor :assigns, :splat, :source
    
    def empty?
      @assigns.nil? and (@splat.equal?(true) or @splat.nil?)
    end
  end
  
  class Define < ClosedScope
    kind :defn
    
    def consume(sexp)
      name, body = sexp
      scope = super([body])
      
      body = scope.block.body
      args = body.shift
      
      if body.first.is? BlockAsArgument
        ba = body.shift
      else
        ba = nil
      end
      
      args.block_arg = ba
            
      return [name, scope, args]
    end
    
    def args(name, body, args)
      @name, @body, @arguments = name, body, args      
    end
        
    attr_accessor :name, :body, :arguments
  end
  
  class DefineSingleton < Define
    kind :defs
    
    def consume(sexp)
      object = sexp.shift
      out = super(sexp)
      out.unshift convert(object)
      
      return out
    end
    
    def args(obj, name, body, args)
      @object = obj
      
      super(name, body, args)
    end
    
    attr_accessor :object
  end
  
  class MethodCall < Node
    
    def initialize(comp)
      super(comp)
      @block = nil
      scope = get(:scope)
      if scope.is? Class
        @scope = :class
      elsif scope.is? Module
        @scope = :module
      elsif scope.is? Script
        @scope = :script
      else
        @scope = :method
      end
    end
    
    attr_accessor :block, :scope
  end
  
  class Call < MethodCall
    kind :call
    
    # Args could be an array, splat or argscat
    def collapse_args
      return unless @arguments
      @arguments = @arguments.body if @arguments.is? ArrayLiteral
    end
    
    def args(object, meth, args=nil)
      @object, @method, @arguments = object, meth, args
      
      collapse_args()
    end
    
    attr_accessor :object, :method, :arguments
    
    def fcall?
      false
    end
    
    def call?
      true
    end
    
    def argcount
      if @arguments.nil?
        return 0
      elsif @arguments.kind_of? Array
        return @arguments.size
      end
      
      return nil
    end
  end
  
  class FCall < Call
    kind :fcall
    
    def normalize(meth, args=nil)
      @method, @arguments = meth, args
      
      collapse_args()
      
      return detect_special_forms()
    end
    
    attr_accessor :method, :arguments
    
    def detect_special_forms
      # Detect ivar as index.
      if @method == :ivar_as_index
        args = @arguments
        if args.size == 1 and args[0].is? ImplicitHash
          family = get(:family)
          hsh = args[0].body
          0.step(hsh.size-1, 2) do |i|
            family.add_ivar_as_slot hsh[i].value, hsh[i+1].value
          end
          
          return nil
        end
      end
      return self
    end
    
    def fcall?
      true
    end
    
    def call?
      false
    end
  end
  
  class VCall < FCall
    kind :vcall
    
    def args(meth)
      @method = meth
      @arguments = nil
    end
    
    attr_accessor :method
  end
  
  class AttrAssign < Call
    kind :attrasgn
    
    def args(obj, meth, args=nil)
      @object, @method = obj, meth
      @arguments = args
      
      # Strange. nil is passed when it's self. Whatevs.
      @object = Self.new @compiler if @object.nil?
            
      if @method.to_s[-1] != ?=
        @method = "#{@method}=".to_sym
      end
      
      collapse_args()
    end
  end
  
  class Super < Call
    kind :super
    
    def args(args)
      @method = get(:scope)
      @arguments = args
      
      collapse_args()
    end
    
    attr_accessor :arguments
  end
  
  class ZSuper < Super
    kind :zsuper
    
    def args
      @method = get(:scope)
    end
  end
  
  class Yield < Call
    kind :yield
    
    def args(args, direct=false)
      if direct and args.kind_of? ArrayLiteral
        @arguments = args.body
      elsif args.kind_of? DynamicArguments
        @arguments = args
      elsif args
        @arguments = [args]
      else
        @arguments = []
      end
    end
    
    attr_accessor :arguments
  end
  
  class BlockAsArgument < Node
    kind :block_arg
    
    def args(name, position=nil)
      @name = name
      
      scope = get(:scope)
      
      @variable, @depth = scope.find_local name
      @variable.in_locals!
    end
    
    attr_accessor :name, :variable, :depth
  end
  
  class Loop < Node
    def args(body)
      @body = body
    end
  end
  
  class IterArgs < Node
    kind :iter_args
    
    def args(child)
      @child = child
    end
    
    def names
      if @child.is? LocalAssignment
        [@child.name]
      else
        @child.assigns.body.map { |i| i.name }
      end
    end
    
    attr_accessor :child
  end
    
  class Iter < Node
    kind :iter
    
    def consume(sexp)
      c = convert(sexp[0])
      sexp[0] = c
      
      # Get rid of the linked list of dasgn_curr's at the top
      # of a block in at iter.
      if sexp.length > 2   # Fix for empty block
        first = sexp[2][1]
        if first.kind_of?(Array) and first[0] == :dasgn_curr
          if first[2].nil? or first[2][0] == :dasgn_curr
            sexp[2].delete_at(1)
          end
        end
      end
      
      if c.is? FCall and c.method == :loop
        sexp[1] = convert(sexp[1])
        sexp[2] = convert(sexp[2])
        return sexp
      end
      
      set(:iter) do
        
        @locals = get(:scope).new_block_scope do
          set(:iter_args) do
            sexp[1] = convert([:iter_args, sexp[1]])
          end
                
          sexp[2] = convert(sexp[2])
        end
      end
      
      sexp
    end
    
    def normalize(c, a, b)
      @arguments, @body = a, b
      
      if c.is? FCall and c.method == :loop
        n = Loop.new(@compiler)
        n.args(b)
        return n
      end
      
      c.block = self
            
      return c
    end
    
    attr_accessor :arguments, :body, :locals
  end

  class For < Iter
    kind :for

    # [[:newline, 1, "(eval)", [:dot2, [:lit, 1], [:lit, 2]]], [:lasgn, :x, 0]]
    # should become
    # [[:call, [:newline, 1, "(eval)", [:dot2, [:lit, 1], [:lit, 2]]], :each], [:lasgn, :x, 0] ]
    def self.create(compiler, sexp)
      # sexp[0] is :for
      # sexp[1] is the enumeration for each
      # sexp[2] is the lasgn of the for argument
      # sexp[3] is the body, if any
      sexp = [sexp[0], [:call, sexp[1], :each], sexp[2], sexp[3]]
      super(compiler, sexp)
    end

    def consume(sexp)
      converted = convert(sexp[0])
      sexp[0] = converted # enum for the 'each' call

      set(:iter_args) do
       sexp[1] = convert([:iter_args, sexp[1]]) # local var assignment
      end

      set(:iter) do
        @locals = get(:scope).new_block_scope do
          sexp[2] = convert(sexp[2]) # body
        end
      end
      
      sexp
    end

    def normalize(c, arguments, body)
      @arguments, @body = arguments, body
      
      c.block = self
      return c
    end
  end
  
  class BlockPass < Node
    kind :block_pass
    
    def normalize(blk, call)
      @block = blk
      
      call.block = self
      return call
    end
    
    attr_accessor :block
  end
  
  class ExecuteString < StringLiteral
    kind :xstr
  end
  
  # "#{foo.bar}"
  #
  # Evstrs appear as a part of a dstr, dynamic string.
  # The evstr part is the code to be evaluated while
  # the dstr puts the whole thing together. 
  #
  # Interestingly, an evstr that only contains string
  # literals such as "#{'foo'}" is parsed to a plain
  # string literal. This is the same for dregx.
  class ToString < Node
    kind :evstr
    
    # Expected input is a sub-sexp that represents the 
    # code to be run when evaluating or empty sexp.
    def consume(sexp)
      sexp = [[:str, ""]] if sexp.empty?
      super(sexp)
    end

    def args(child)
      @child = child
    end
    
    attr_accessor :child
  end
    
  class DynamicExecuteString < DynamicString
    kind :dxstr
  end
  
  class DynamicSymbol < Node
    kind :dsym
    
    def args(string)
      @string = string
    end
  end
    
  class Alias < Node
    kind :alias
    
    def args(current, name)
      @current, @new = current, name
    end
    
    attr_accessor :current, :new
  end
  
  class Range < Node
    kind :dot2
    
    def args(start, fin)
      @start, @finish = start, fin
    end
    
    attr_accessor :start, :finish
  end
  
  class RangeExclude < Range
    kind :dot3
  end
  
  class CVarAssign < Node
    kind :cvasgn
    
    def args(name, val)
      @name, @value = name, val
    end
    
    attr_accessor :name, :value
  end
  
  class CVarDeclare < CVarAssign
    kind :cvdecl
  end
  
  class CVar < Node
    kind :cvar
    
    def args(name)
      @name = name
    end
    
    attr_accessor :name
  end
end
end