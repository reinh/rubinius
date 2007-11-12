class Compiler::Node
  
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
      Hash.new { |h,k| h[k] = Compiler::Local.new(self, k) }
    end
    
    attr_accessor :use_eval, :locals
    
    def consume(sexp)
      position(:scope, self) do
        position(:visibility, :public) do
          out = convert(sexp[0])
          @all_scopes.each do |scope|
            scope.each do |k,v|
              v.formalize!
            end
          end
          out
        end
      end
    end
    
    def depth
      @block_scope.size
    end
    
    def new_block_scope
      begin
        scope = create_scope();
        @block_scope << scope
        @all_scopes << scope
        yield
      ensure
        @block_scope.pop
      end
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
          lcl = @block_scope.last[name]
          lcl.created_in_block!
          dep = 0  
        end
      end
      
      lcl.access_in_block!
      
      return [lcl, dep]
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
      position(:family, self) do
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
  end
  
  class Newline < Node
    kind :newline
    
    def args(line, file, child)
      @line, @file, @child = line, file, child
    end
    
    attr_accessor :line, :file, :child
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
    
    def consume(args)
      if args.size == 1 or args[0].nil?
        return [nil, nil]
      end
      
      args[0] = convert(args[0])
      return args
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
    def consume(args)
      
      if args.empty?
        return [[], [], nil, nil]
      end
      
      # Strip the parser calculated index of splat
      if args[2] and args[2].size == 2
        args[2] = args[2].first
      end
      
      defaults = args[3]
      
      if defaults
        defaults.shift
        defaults.map! do |node|
          convert(node)
        end
        
        args[3] = defaults
      end
      
      args
    end
    
    def args(req, optional, splat, defaults)
      @required, @optional, @splat, @defaults = req, optional, splat, defaults
      populate
    end
    
    attr_accessor :required, :optional, :splat, :defaults
    
    def populate
      i = 0
      scope = position?(:scope)
      
      @required.each do |var|
        var, depth = scope.find_local(var)
        var.argument!(i)
        i += 1
      end
      
      @optional.each do |var|
        var, depth = scope.find_local(var)
        var.argument!(i)
        i += 1
      end
      
      if @splat
        var, depth = scope.find_local(splat)
        var.argument!(i)
      end
    end
  end
  
  class Undef < Node
    kind :undef
    
    def args(name)
      @name = name
    end
    
    attr_accessor :name
  end
  
  class Break < Node
    kind :break
    def args(value=nil)
      @value = value
      @in_block = position?(:iter)
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
    
    def args(cond, body)
      @body = body
      @conditions = []
      @splat = nil
      
      if cond.kind_of? ArrayLiteral      
        cond.body.each do |c|
          # Inner when means splat.
          if c.kind_of? When
            @splat = c.splat
          else
            @conditions << c
          end
        end
      else
        @splat = cond
      end
    end
    
    attr_reader :body, :condition, :splat
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
    
    attr_accessor :receiver, :whens, :else
  end
  
  class LocalVariable < Node
    def args(name)
      scope = position?(:scope)
      
      if position?(:iter)
        @variable, @depth = scope.find_local name, true
      else
        @variable, @depth = scope.find_local name
      end
      
      @name = name
    end
  end

  class LocalAssignment < LocalVariable
    kind :lasgn
    
    def args(name, idx, val=nil)
      if val.nil? and !position?(:iter_args)
        raise ArgumentError, "value can not be nil"
      end
            
      @value = val
      super(name)
    end
    
    attr_accessor :name, :value, :variable
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
  
  class Splat < Node
    kind :splat
    
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
    
    def args(obj, kind, value)
      @object, @kind = obj, kind
      @index = value.body[1]
      @value = value.body[0]
    end
    
    attr_accessor :object, :kind, :value, :extra
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
  
  class ConcatArgs < DynamicArguments
    kind :argscat
    
    def args(rest, array)
      @array, @rest = array, rest
    end
    
    attr_accessor :array, :rest
  end
  
  class PushArgs < DynamicArguments
    kind :argspush
    
    def args(array, item)
      @item = item
      unless array.kind_of? Splat
        raise Error, "Unknown form of argspush"
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
      if idx = position?(:family).find_ivar_index(name)
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
    
    def normalize(name, val)
      if idx = position?(:family).find_ivar_index(name)
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
    
    def args(name, value)
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
      elsif complex.kind_of? ConstAtTop
        @from_top = true
        @name = complex.name
      else
        @parent = complex.parent
        @name = complex.name
      end
    end
    
    attr_accessor :parent, :value, :name
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
      
      if name.kind_of? ConstFind
        parent = nil
      else
        parent = name.parent
      end
      
      body = position(:family, self) do
        super([sexp[2]])
      end
            
      [sym, parent, convert(sexp[1]), body]
    end
    
    attr_accessor :name, :superclass, :body
  end
  
  class Module < ClosedScope
    kind :module
    
    def args(name, parent, body)
      @name, @parent, @body = name, parent, body
    end
    
    def consume(sexp)
      name = convert(sexp[0])
      sym = name.name
      
      if name.kind_of? ConstFind
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
      if cond.kind_of? ArrayLiteral
        @conditions = cond.body
        @splat = nil
      elsif cond.kind_of? Splat
        @conditions = nil
        @splat = cond.child
      elsif cond.kind_of? ConcatArgs
        @conditions = cond.rest.body
        @splat = cond.array
      elsif cond.nil?
        cf = ConstFind.new(@compiler)
        cf.args :StandardError
        @conditions = [cf]
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
        position(:in_rescue) do
          res = convert(body)
        end
        els = nil
      elsif els.nil?
        if body.first == :resbody
          body = nil
          
          els = convert(res)
          
          position(:in_rescue) do
            res = convert(body)
          end
        else
          body = convert(body)
          position(:in_rescue) do
            res = convert(res)
          end
          els = nil
        end
      else
        body = convert(body)
        position(:in_rescue) do
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
      position(:in_ensure, opts) do
        sexp[0] = convert(sexp[0])
      end
      
      # Propagate did_return up to an outer ensure
      if ens = position?(:in_ensure)
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
      @in_rescue = position?(:in_rescue)
      
      if ens = position?(:in_ensure)
        ens[:did_return] = true
        @in_ensure = true
      else
        @in_ensure = false
      end
      
      @in_block = position?(:iter)
    end
    
    attr_accessor :value, :in_rescue, :in_ensure, :in_block
  end
  
  class MAsgn < Node
    kind :masgn
    
    def args(assigns, splat, source=nil)
      if source.nil?
        @assigns = nil
        @splat = assigns
        @source = splat
      else
        @assigns, @splat, @source = assigns, splat, source
      end
      
      @in_block = position?(:iter)
    end
    
    attr_accessor :left, :splat, :source
    
    def empty?
      @left == nil and (@splat == true or splat.nil?)
    end
  end
  
  class Define < ClosedScope
    kind :defn
    
    def consume(sexp)
      name, body = sexp
      scope = super([body])
      
      args = scope.block.body.shift
      
      return [name, scope, args]
    end
    
    def args(name, body, args)
      @name, @body, @arguments = name, body, args
    end
        
    attr_accessor :name, :body
  end
  
  class DefineSingleton < Define
    kind :defs
    
    def consume(sexp)
      sexp = super(sexp)
      sexp[0] = convert(sexp[0])
      return sexp
    end
    
    def args(obj, name, body, args)
      @object, @name, @body, @arguments = obj, name, body, args
    end
    
    attr_accessor :object, :name, :body
  end
  
  class MethodCall < Node
    
    def initialize(comp)
      super(comp)
      @block = nil
      scope = position?(:scope)
      if scope.kind_of? Class
        @scope = :class
      elsif scope.kind_of? Module
        @scope = :module
      elsif scope.kind_of? Script
        @scope = :script
      else
        @scope = :method
      end
    end
    
    attr_accessor :block, :scope
  end
  
  class Call < MethodCall
    kind :call
    
    def args(object, meth, args=nil)
      @object, @method, @arguments = object, meth, args
    end
    
    attr_accessor :object, :method, :arguments
  end
  
  class FCall < Call
    kind :fcall
    
    def normalize(meth, args=nil)
      @method, @arguments = meth, args
      
      return detect_special_forms()
    end
    
    attr_accessor :method, :arguments
    
    def detect_special_forms
      # Detect ivar as index.
      if @method == :ivar_as_index
        args = @arguments.body
        if args.size == 1 and args[0].kind_of? ImplicitHash
          family = position?(:family)
          hsh = args[0].body
          0.step(hsh.size-1, 2) do |i|
            family.add_ivar_as_slot hsh[i].value, hsh[i+1].value
          end
          
          return nil
        end
      end
      return self
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
    
    def args(obj, meth, args)
      @object, @method = obj, meth
      @arguments = args
    end
  end
  
  class Super < Node
    kind :super
    
    def args(args)
      @arguments = args
    end
    
    attr_accessor :arguments
  end
  
  class ZSuper < Super
    kind :zsuper
    
    def args
    end
  end
  
  class BlockPass < Node
    kind :block_pass
    
    def args(blk, call)
      @block, @call = blk, call
    end
    
    attr_accessor :block, :call
  end
  
  class BlockAsArgument < Node
    kind :block_arg
    
    def args(name, position)
      @name = name
    end
    
    attr_accessor :name
  end
  
  class Loop < Node
    def args(body)
      @body = body
    end
  end
    
  class Iter < Node
    kind :iter
    
    def consume(sexp)
      c = convert(sexp[0])
      sexp[0] = c
      
      if c.kind_of? FCall and c.method == :loop
        sexp[1] = convert(sexp[1])
        sexp[2] = convert(sexp[2])
        return sexp
      end
      
      position(:iter) do
        
        position?(:scope).new_block_scope do
          position(:iter_args) do
            sexp[1] = convert(sexp[1])
          end
        
          # Get rid of the linked list of dasgn_curr's at the top
          # of a block in at iter.
          first = sexp[2][1]
          if first.kind_of?(Array) and first[0] == :dasgn_curr
            if first[2].nil? or first[2][0] == :dasgn_curr
              sexp[2].delete_at(1)
            end
          end
        
          sexp[2] = convert(sexp[2])
        end
      end
      
      sexp
    end
    
    def normalize(c, a, b)
      @arguments, @body = a, b
      
      if c.kind_of? FCall and c.method == :loop
        n = Loop.new(@compiler)
        n.args(b)
        return n
      end
      
      c.block = self
            
      return c
    end
    
    attr_accessor :arguments, :body
  end
  
  class ExecuteString < StringLiteral
    kind :xstr
  end
  
  class ToString < Node
    kind :evstr
    
    def args(child)
      @child = child
    end
    
    attr_accessor :child
  end
    
  class DynamicExecuteString < DynamicString
    kind :dxstr
  end
  
  class DynamicSymbol < DynamicString
    kind :dsym
  end
  
  class Yield < Node
    kind :yield
    
    def args(args)
      @arguments = args
    end
    
    attr_accessor :arguments
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
  
  class RangExclude < Range
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