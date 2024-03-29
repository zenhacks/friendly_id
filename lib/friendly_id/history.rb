module FriendlyId

=begin

== History: Avoiding 404's When Slugs Change

FriendlyId's {FriendlyId::History History} module adds the ability to store a
log of a model's slugs, so that when its friendly id changes, it's still
possible to perform finds by the old id.

The primary use case for this is avoiding broken URLs.

=== Setup

In order to use this module, you must add a table to your database schema to
store the slug records. FriendlyId provides a generator for this purpose:

  rails generate friendly_id
  rake db:migrate

This will add a table named +friendly_id_slugs+, used by the {FriendlyId::Slug}
model.

=== Considerations

This module is incompatible with the +:scoped+ module.

Because recording slug history requires creating additional database records,
this module has an impact on the performance of the associated model's +create+
method.

=== Example

    class Post < ActiveRecord::Base
      extend FriendlyId
      friendly_id :title, :use => :history
    end

    class PostsController < ApplicationController

      before_filter :find_post

      ...

      def find_post
        @post = Post.find params[:id]

        # If an old id or a numeric id was used to find the record, then
        # the request path will not match the post_path, and we should do
        # a 301 redirect that uses the current friendly id.
        if request.path != post_path(@post)
          return redirect_to @post, :status => :moved_permanently
        end
      end
    end
=end
  module History

    # Configures the model instance to use the History add-on.
    def self.included(model_class)
      model_class.instance_eval do
        @friendly_id_config.use :slugged
        has_many :slugs,
                 :as => :sluggable, :dependent => :destroy,
                 :class_name => Slug.to_s
        after_save :create_slug
        relation_class.send :include, FinderMethods
        friendly_id_config.slug_generator_class.send :include, SlugGenerator

        def slugs
          super.order "#{Slug.quoted_table_name}.id DESC"
        end
      end
    end

    private

    def create_slug
      return unless friendly_id
      return if slugs.first.try(:slug) == friendly_id
      # Allow reversion back to a previously used slug
      relation = slugs.where(:slug => friendly_id)
      result = relation.select("id").lock(true)
      relation.delete_all unless result.empty?
      slugs.create! do |record|
        record.slug = friendly_id
        record.scope = serialized_scope if friendly_id_config.uses?(:scoped)
      end
    end

    # Adds a finder that explictly uses slugs from the slug table.
    module FinderMethods

      # Search for a record in the slugs table using the specified slug.
      def find_one(id)
        return super(id) if id.unfriendly_id?
        where(@klass.friendly_id_config.query_field => id).first or
        with_old_friendly_id(id) {|x| where(:id => x).first} or
        find_one_without_friendly_id(id)
      end

      # Search for a record in the slugs table using the specified slug.
      def exists?(conditions = :none)
        return super if conditions.unfriendly_id?
        exists_without_friendly_id?(@klass.friendly_id_config.query_field => conditions) ||
          with_old_friendly_id(conditions) {|x| exists_without_friendly_id?(:id => x)} ||
          exists_without_friendly_id?(conditions)
      end

      private

      # Accepts a slug, and yields a corresponding sluggable_id into the block.
      def with_old_friendly_id(slug, &block)
        sql = "SELECT sluggable_id FROM #{Slug.quoted_table_name} WHERE sluggable_type = %s AND slug = %s"
        sql = sql % [@klass.base_class.to_s, slug].map {|x| self.connection.quote(x)}
        sluggable_ids = self.connection.select_values(sql)
        yield sluggable_ids if sluggable_ids
      end
    end

    # This module overrides {FriendlyId::SlugGenerator#conflicts} to consider
    # all historic slugs for that model.
    module SlugGenerator

      private

      def conflicts
        sluggable_class = friendly_id_config.model_class.base_class
        pkey            = sluggable_class.primary_key
        value           = sluggable.send pkey

        scope = Slug.where("slug = ? OR slug LIKE ?", normalized, wildcard)
        scope = scope.where(:sluggable_type => sluggable_class.to_s)
        scope = scope.where("sluggable_id <> ?", value) unless sluggable.new_record?
        if sluggable.friendly_id_config.uses?(:scoped)
          scope = scope.where("scope = ?", sluggable.serialized_scope)
        end
        length_command = "LENGTH"
        length_command = "LEN" if sluggable.class.connection.adapter_name =~ /sqlserver/i
        scope.order("#{length_command}(slug) DESC, slug DESC")
      end
    end
  end
end
