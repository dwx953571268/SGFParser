require 'stringio'

module SGF

  #The parser returns a SGF::Collection representation of the SGF file
  #parser = SGF::Parser.new
  #collection = parser.parse sgf_in_string_form
  class Parser

    # Fields and where they're used:
    #
    # @sgf_stream
    #   parse, parse_node_data, parse_identity, parse_comment,
    #   parse_multi_property, parse_generic_property
    #
    # @collection
    #   parse
    #
    # @current_node
    #   parse, open_branch, close_branch, create_new_node,
    #   add_properties_to_current_node
    #
    # @branches
    #   parse, open_branch, close_branch
    #
    # @node_properties
    #   parse_node_data, add_properties_to_current_node
    #
    # @identity
    #   parse_node_data, parse_identity, parse_property
    #
    # @property
    #   parse_node_data, parse_property, parse_comment,
    #   parse_multi_property, parse_generic_property, still_inside_comment

    NEW_NODE = ";"
    BRANCHING = %w{( )}
    END_OF_FILE = false
    NODE_DELIMITERS = [NEW_NODE].concat(BRANCHING).concat([END_OF_FILE])
    PROPERTY = %w([ ])
    LIST_IDENTITIES = %w(AW AB AE AR CR DD LB LN MA SL SQ TR VW TB TW)

    # This takes as argument an SGF and returns an SGF::Collection object
    # It accepts a local path (String), a stringified SGF (String),
    # or a file handler (File).
    # The second argument is optional, in case you don't want this to raise errors.
    # You probably shouldn't use it, but who's gonna stop you?
    def parse sgf, strict_parsing = true
      error_checker = strict_parsing ? StrictErrorChecker.new : LaxErrorChecker.new
      @sgf_stream = SgfStream.new(sgf, error_checker)
      @collection = Collection.new
      @current_node = @collection.root
      @branches = []
      until @sgf_stream.eof?
        case @sgf_stream.next_character
          when "(" then open_branch
          when ";" then
            create_new_node
            parse_node_data
            add_properties_to_current_node
          when ")" then close_branch
          else next
        end
      end
      @collection
    end

    private

    def open_branch
      @branches.unshift @current_node
    end

    def close_branch
      @current_node = @branches.shift
    end

    def create_new_node
      node = SGF::Node.new
      @current_node.add_children node
      @current_node = node
    end

    def parse_node_data
      @node_properties = {}
      while still_inside_node?
        parse_identity
        parse_property
        @node_properties[@identity] = @property
      end
    end

    def still_inside_node?
      !NODE_DELIMITERS.include?(@sgf_stream.peek_skipping_whitespace)
    end

    def add_properties_to_current_node
      @current_node.add_properties @node_properties
    end

    def parse_identity
      @identity = ""
      while char = @sgf_stream.next_character and char != "["
        @identity << char unless char == "\n"
      end
    end

    def parse_property
      @property = ""
      format = lookup_format
      parse_comment format
    end
    
    def lookup_format
      case @identity.upcase
        when "C" then CommentFormat.new
        when *LIST_IDENTITIES then MultiPropertyFormat.new
        else GenericPropertyFormat.new
      end
    end

    def parse_comment format
      while char = @sgf_stream.next_character and format.still_inside? char, @property, @sgf_stream
        @property << char
      end
      @property = format.transform @property
    end
  end

end

class CommentFormat
  def still_inside? char, property, sgf_stream
    char != "]" || (char == "]" && property[-1..-1] == "\\")
  end

  def transform property
    property.gsub "\\]", "]"
  end
end

class MultiPropertyFormat
  def still_inside? char, property, sgf_stream
    return true if char != "]"
    sgf_stream.peek_skipping_whitespace == "["
  end

  def transform property
    property.gsub("][", ",").split(",")
  end
end

class GenericPropertyFormat
  def still_inside? char, property, sgf_stream
    char != "]"
  end
  
  def transform property
    property
  end
end

class StrictErrorChecker
  def check_for_errors_before_parsing string
    unless string[/\A\s*\(\s*;/]
      msg = "The first two non-whitespace characters of the string should be (;"
      msg << " but they were #{string[0..1]} instead."
      raise(SGF::MalformedDataError, msg)
    end
  end
end

class LaxErrorChecker
  def check_for_errors_before_parsing string
    # just look the other way
  end
end

class SgfStream
  attr_reader :stream

  def initialize sgf, error_checker
    sgf = sgf.read if sgf.instance_of?(File)
    sgf = File.read(sgf) if File.exist?(sgf)
    error_checker.check_for_errors_before_parsing sgf
    @stream = StringIO.new clean(sgf), 'r'
  end

  def eof?
    @stream.eof?
  end

  def next_character
    !@stream.eof? && @stream.sysread(1)
  end

  def peek_skipping_whitespace
    while char = next_character
      next if char[/\s/]
      break
    end
    rewind if char
    char
  end

  private

  def rewind
    @stream.pos -= 1
  end

  def clean sgf
    sgf.gsub! "\\\\n\\\\r", ''
    sgf.gsub! "\\\\r\\\\n", ''
    sgf.gsub! "\\\\r", ''
    sgf.gsub! "\\\\n", ''
    sgf
  end
end
