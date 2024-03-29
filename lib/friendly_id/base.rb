module FriendlyId
=begin

== Setting Up FriendlyId in Your Model

To use FriendlyId in your ActiveRecord models, you must first either extend or
include the FriendlyId module (it makes no difference), then invoke the
{FriendlyId::Base#friendly_id friendly_id} method to configure your desired
options:

    class Foo < ActiveRecord::Base
      include FriendlyId
      friendly_id :bar, :use => [:slugged, :simple_i18n]
    end

The most important option is `:use`, which you use to tell FriendlyId which
addons it should use. See the documentation for this method for a list of all
available addons, or skim through the rest of the docs to get a high-level
overview.

=== The Default Setup: Simple Models

The simplest way to use FriendlyId is with a model that has a uniquely indexed
column with no spaces or special characters, and that is seldom or never
updated. The most common example of this is a user name:

    class User < ActiveRecord::Base
      extend FriendlyId
      friendly_id :login
      validates_format_of :login, :with => /\A[a-z0-9]+\z/i
    end

    @user = User.find "joe"   # the old User.find(1) still works, too
    @user.to_param            # returns "joe"
    redirect_to @user         # the URL will be /users/joe

In this case, FriendlyId assumes you want to use the column as-is; it will never
modify the value of the column, and your application should ensure that the
value is unique and admissible in a URL:

    class City < ActiveRecord::Base
      extend FriendlyId
      friendly_id :name
    end

    @city.find "Viña del Mar"
    redirect_to @city # the URL will be /cities/Viña%20del%20Mar

Writing the code to process an arbitrary string into a good identifier for use
in a URL can be repetitive and surprisingly tricky, so for this reason it's
often better and easier to use {FriendlyId::Slugged slugs}.

=end
  module Base

    # Configure FriendlyId's behavior in a model.
    #
    #   class Post < ActiveRecord::Base
    #     extend FriendlyId
    #     friendly_id :title, :use => :slugged
    #   end
    #
    # When given the optional block, this method will yield the class's instance
    # of {FriendlyId::Configuration} to the block before evaluating other
    # arguments, so configuration values set in the block may be overwritten by
    # the arguments. This order was chosen to allow passing the same proc to
    # multiple models, while being able to override the values it sets. Here is
    # a contrived example:
    #
    #   $friendly_id_config_proc = Proc.new do |config|
    #     config.base = :name
    #     config.use :slugged
    #   end
    #
    #   class Foo < ActiveRecord::Base
    #     extend FriendlyId
    #     friendly_id &$friendly_id_config_proc
    #   end
    #
    #   class Bar < ActiveRecord::Base
    #     extend FriendlyId
    #     friendly_id :title, &$friendly_id_config_proc
    #   end
    #
    # However, it's usually better to use {FriendlyId.defaults} for this:
    #
    #   FriendlyId.defaults do |config|
    #     config.base = :name
    #     config.use :slugged
    #   end
    #
    #   class Foo < ActiveRecord::Base
    #     extend FriendlyId
    #   end
    #
    #   class Bar < ActiveRecord::Base
    #     extend FriendlyId
    #     friendly_id :title
    #   end
    #
    # In general you should use the block syntax either because of your personal
    # aesthetic preference, or because you need to share some functionality
    # between multiple models that can't be well encapsulated by
    # {FriendlyId.defaults}.
    #
    # === Order Method Calls in a Block vs Ordering Options
    #
    # When calling this method without a block, you may set the hash options in
    # any order.
    #
    # However, when using block-style invocation, be sure to call
    # FriendlyId::Configuration's {FriendlyId::Configuration#use use} method
    # *prior* to the associated configuration options, because it will include
    # modules into your class, and these modules in turn may add required
    # configuration options to the +@friendly_id_configuraton+'s class:
    #
    #   class Person < ActiveRecord::Base
    #     friendly_id do |config|
    #       # This will work
    #       config.use :slugged
    #       config.sequence_separator = ":"
    #     end
    #   end
    #
    #   class Person < ActiveRecord::Base
    #     friendly_id do |config|
    #       # This will fail
    #       config.sequence_separator = ":"
    #       config.use :slugged
    #     end
    #   end
    #
    # === Including Your Own Modules
    #
    # Because :use can accept a name or a Module, {FriendlyId.defaults defaults}
    # can be a convenient place to set up behavior common to all classes using
    # FriendlyId. You can include any module, or more conveniently, define one
    # on-the-fly. For example, let's say you want to make
    # Babosa[http://github.com/norman/babosa] the default slugging library in
    # place of Active Support, and transliterate all slugs from Russian Cyrillic
    # to ASCII:
    #
    #   require "babosa"
    #
    #   FriendlyId.defaults do |config|
    #     config.base = :name
    #     config.use :slugged
    #     config.use Module.new {
    #       def normalize_friendly_id(text)
    #         text.to_slug.normalize(:transliterations => [:russian, :latin])
    #       end
    #     }
    #   end
    #
    #
    # @option options [Symbol,Module] :use The addon or name of an addon to use.
    #   By default, FriendlyId provides {FriendlyId::Slugged :slugged},
    #   {FriendlyId::History :history}, {FriendlyId::Reserved :reserved}, and
    #   {FriendlyId::Scoped :scoped}, {FriendlyId::SimpleI18n :simple_i18n},
    #   and {FriendlyId::Globalize :globalize}.
    #
    # @option options [Array] :reserved_words Available when using +:reserved+,
    #   which is loaded by default. Sets an array of words banned for use as
    #   the basis of a friendly_id. By default this includes "edit" and "new".
    #
    # @option options [Symbol] :scope Available when using +:scoped+.
    #   Sets the relation or column used to scope generated friendly ids. This
    #   option has no default value.
    #
    # @option options [Symbol] :sequence_separator Available when using +:slugged+.
    #   Configures the sequence of characters used to separate a slug from a
    #   sequence. Defaults to +--+.
    #
    # @option options [Symbol] :slug_column Available when using +:slugged+.
    #   Configures the name of the column where FriendlyId will store the slug.
    #   Defaults to +:slug+.
    #
    # @option options [Symbol] :slug_generator_class Available when using +:slugged+.
    #   Sets the class used to generate unique slugs. You should not specify this
    #   unless you're doing some extensive hacking on FriendlyId. Defaults to
    #   {FriendlyId::SlugGenerator}.
    #
    # @yield Provides access to the model class's friendly_id_config, which
    #   allows an alternate configuration syntax, and conditional configuration
    #   logic.
    #
    # @yieldparam config The model class's {FriendlyId::Configuration friendly_id_config}.
    def friendly_id(base = nil, options = {}, &block)
      yield friendly_id_config if block_given?
      friendly_id_config.use options.delete :use
      friendly_id_config.send :set, base ? options.merge(:base => base) : options
      before_save {|rec| rec.instance_eval {@current_friendly_id = friendly_id}}
      include Model
    end

    # Returns the model class's {FriendlyId::Configuration friendly_id_config}.
    # @note In the case of Single Table Inheritance (STI), this method will
    #   duplicate the parent class's FriendlyId::Configuration and relation class
    #   on first access. If you're concerned about thread safety, then be sure
    #   to invoke {#friendly_id} in your class for each model.
    def friendly_id_config
      @friendly_id_config ||= base_class.friendly_id_config.dup.tap do |config|
        config.model_class = self
        @relation_class = base_class.send(:relation_class)
      end
    end

    private

    # Gets an instance of an the relation class.
    #
    # With FriendlyId this will be a subclass of ActiveRecord::Relation, rather than
    # Relation itself, in order to avoid tainting all Active Record models with
    # FriendlyId.
    #
    # Note that this method is essentially copied and pasted from Rails 3.2.9.rc1,
    # with the exception of changing the relation class. Obviously this is less than
    # ideal, but I know of no better way to accomplish this.
    # @see #relation_class
    def relation #:nodoc:
      relation = relation_without_friendly_id

      if finder_needs_type_condition?
        relation.where(type_condition).create_with(inheritance_column.to_sym => sti_name)
      else
        inject_friendly_id(relation)
      end
    end

    # Includes friendly_id methods into relation class
    #
    # Rather than including FriendlyId's overridden finder methods in
    # ActiveRecord::Relation directly, FriendlyId adds them to a subclass
    # specific to the AR model, and makes #relation return an instance of this
    # class. By doing this, we ensure that only models that specifically extend
    # FriendlyId have their finder methods overridden.
    #
    # Note that this method does not directly subclass ActiveRecord::Relation,
    # but rather whatever class the @relation class instance variable is an
    # instance of.  In practice, this will almost always end up being
    # ActiveRecord::Relation, but in case another plugin is using this same
    # pattern to extend a model's finder functionality, FriendlyId will not
    # replace it, but rather override it.
    #
    # This pattern can be seen as a poor man's "refinement"
    # (http://timelessrepo.com/refinements-in-ruby), and while I **think** it
    # will work quite well, I realize that it could cause unexpected issues,
    # since the authors of Rails are probably not intending this kind of usage
    # against a private API. If this ends up being problematic I will probably
    # revert back to the old behavior of simply extending
    # ActiveRecord::Relation.
    def inject_friendly_id(klass)
      klass.class.class_eval do
        alias_method :find_one_without_friendly_id, :find_one
        alias_method :exists_without_friendly_id?, :exists?
        include FriendlyId::FinderMethods
      end

      klass
    end

    # Gets (and if necessary, creates) a subclass of the model's relation class.
    def relation_class
      @relation_class or begin
        @relation_class = inject_friendly_id(relation_without_friendly_id).class
      end
    end
  end

  # Instance methods that will be added to all classes using FriendlyId.
  module Model

    attr_reader :current_friendly_id

    # Convenience method for accessing the class method of the same name.
    def friendly_id_config
      self.class.friendly_id_config
    end

    # Get the instance's friendly_id.
    def friendly_id
      send friendly_id_config.query_field
    end

    # Either the friendly_id, or the numeric id cast to a string.
    def to_param
      if diff = changes[friendly_id_config.query_field]
        diff.first || diff.second
      else
        friendly_id.presence || super
      end
    end
  end
end
