#  Created by Ari Brown on 2008-02-23.
#  For rubinius. All pwnage reserved.
#  
#  Used in pwning teh nubs with FFI instead of C

# ** Syslog(Module)

# Included Modules: Syslog::Constants

# require 'syslog'

# A Simple wrapper for the UNIX syslog system calls that might be handy
# if you're writing a server in Ruby.  For the details of the syslog(8)
# architecture and constants, see the syslog(3) manual page of your
# platform.

module Syslog
  class << self
    include Constants

    module Foreign
      # methods
      attach_function "openLog", :open, [:string, :int, :int], :void
      attach_function "closeLog", :close, [], :void
      attach_function "syslog", :write, [:int, :string, :string], :void
      attach_function "setlogmask", :set_mask, [:int], :void
      attach_function "LOG_UPTO", :LOG_UPTO, [:int], :int
      attach_function "LOG_MASK", :LOG_MASK, [:int], :int
    end

    module Constants
      # constants
      syslog_constants = %w{
        LOG_EMERG
        LOG_ALERT
        LOG_ERR
        LOG_CRIT
        LOG_WARNING
        LOG_NOTICE
        LOG_INFO
        LOG_DEBUG
        LOG_PID
        LOG_CONS
        LOG_ODELAY
        LOG_NODELAY
        LOG_NOWAIT
        LOG_PERROR
        LOG_AUTH
        LOG_AUTHPRIV
        LOG_CONSOLE
        LOG_CRON
        LOG_DAEMON
        LOG_FTP
        LOG_KERN
        LOG_LPR
        LOG_MAIL
        LOG_NEWS
        LOG_NTP
        LOG_SECURITY
        LOG_SYSLOG
        LOG_USER
        LOG_UUCP
        LOG_LOCAL0
        LOG_LOCAL1
        LOG_LOCAL2
        LOG_LOCAL3
        LOG_LOCAL4
        LOG_LOCAL5
        LOG_LOCAL6
        LOG_LOCAL7
      }.each do |c|
        const_set(c, Rubinius::RUBY_CONFIG['rbx.platform.syslog.' + c])
      end
    end
    
    ##
    # returns the ident of the last open call
    def ident; @ident ||= nil; end
    
    ##
    # returns the options of the last open call
    def options; @options ||= -1; end
    
    ##
    # returns the facility of the last open call
    def facility; @facility ||= -1; end
    
    ##
    # mask
    #   mask=(mask)
    #
    # Returns or sets the log priority mask.  The value of the mask
    # is persistent and will not be reset by Syslog::open or
    # Syslog::close.
    #
    # Example:
    #   Syslog.mask = Syslog::LOG_UPTO(Syslog::LOG_ERR)
    def mask; @mask ||= -1; end
    attr_writer :mask

    ##
    #   open(ident = $0, logopt = Syslog::LOG_PID | Syslog::LOG_CONS, facility = Syslog::LOG_USER) [{ |syslog| ... }]
    #
    # Opens syslog with the given options and returns the module
    # itself.  If a block is given, calls it with an argument of
    # itself.  If syslog is already opened, raises RuntimeError.
    #
    # Examples:
    #   Syslog.open('ftpd', Syslog::LOG_PID | Syslog::LOG_NDELAY, Syslog::LOG_FTP)
    #   open!(ident = $0, logopt = Syslog::LOG_PID | Syslog::LOG_CONS, facility = Syslog::LOG_USER)
    #   reopen(ident = $0, logopt = Syslog::LOG_PID | Syslog::LOG_CONS, facility = Syslog::LOG_USER)
    def open(ident=nil, opt=nil, fac=nil)
      raise "Syslog already open" unless @closed

      @ident = ident
      @options = opt
      @facility = fac

      ident ||= $0
      opt = LOG_PID | LOG_CONS
      fac = LOG_USER

      Foreign.open(ident, opt, fac)

      @opened = true
      @mask = Foreign.setlogmask(0)

      if block_given?
        begin
          yield self
        ensure
          close
        end
      end

      self
    end
    alias :open!, :open

    ##
    # like open, but closes it first
    def reopen(*args)
      close
      open(*args)
    end

    ##
    # Is it open?
    def opened?
      @opened
    end

    ##
    # Close the log
    # close will raise an error if it is already closed
    def close
      raise "Syslog not opened" unless @opened

      Foreign.close
      @ident = nil
      @options = @facility = @mask = -1;
      @opened = false
    end

    ##
    #   log(Syslog::LOG_CRIT, "The %s is falling!", "sky")
    #  
    # Doesn't take any platform specific printf statements
    #   logs things to $stderr
    #   log(Syslog::LOG_CRIT, "Welcome, %s, to my %s!", "leethaxxor", "lavratory")
    def log(pri, *args)
      write(pri, *args)
    end

    ##
    # handy little shortcut for LOG_EMERG as the priority
    def emerg(*args);  Foreign.write(LOG_EMERG,   *args); end
    
    ##
    # handy little shortcut for LOG_ALERT as the priority
    def alert(*args);  Foreign.write(LOG_ALERT,   *args); end
    
    ##
    # handy little shortcut for LOG_ERR as the priority
    def err(*args);    Foreign.write(LOG_ERR,     *args); end
    
    ##
    # handy little shortcut for LOG_CRIT as the priority
    def crit(*args);   Foreign.write(LOG_CRIT,    *args); end
    
    ##
    # handy little shortcut for LOG_WARNING as the priority
    def warning(*args);Foreign.write(LOG_WARNING, *args); end
    
    ##
    # handy little shortcut for LOG_NOTICE as the priority
    def notice(*args); Foreign.write(LOG_NOTICE,  *args); end
    
    ##
    # handy little shortcut for LOG_INFO as the priority
    def info(*args);   Foreign.write(LOG_INFO,    *args); end
    
    ##
    # handy little shortcut for LOG_DEBUG as the priority
    def debug(*args);  Foreign.write(LOG_DEBUG,   *args); end

    ##
    #   LOG_MASK(pri)
    #  
    # Creates a mask for one priority.
    def LOG_MASK
      Foreign.LOG_MASK(pri)
    end

    ##
    #   LOG_UPTO(pri)
    #  
    # Creates a mask for all priorities up to pri.
    def LOG_UPTO pri
      Foreign.LOG_UPTO(pri)
    end

    def inspect
      if @opened
        "#<%s: opened=true, ident=\"%s\", options=%d, facility=%d, mask=%d>" %
        [self.name,
          @ident,
          @options,
          @facility,
          @mask]
        else
          "#<#{self.name}: opened=false>"
        end
      end

      ##
      #   Syslog.instance # => Syslog
      # Returns the Syslog module
      def instance
        self
      end

      def write(pri, format, *args)
        raise "Syslog must be opened before write" unless @opened

        message = format % args
        Foreign.syslog(pri, "%s", message)
      end
      private :write
    end
  end
end