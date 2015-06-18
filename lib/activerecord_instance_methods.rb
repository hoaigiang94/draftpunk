module DraftPunk
  module Model
    module ActiveRecordInstanceMethods
      #############################
      # BEGIN CONFIGURABLE METHODS
      # You can overwrite these methods in your model for custom behavior
      #############################

      # Determines whether to edit a draft, or the original object. This only controls
      # the object returned by editable version, and draft publishing. If changes to not
      # require approval, publishing of the draft is short circuited and will do nothing.
      #
      # Overwrite in your model to implement logic for whether to use a draft.
      #
      # @return [Boolean]
      def changes_require_approval?
        true # By default, all changes require approval
      end

      # Which attributes of this model are published from the draft to the approved object. Overwrite in model
      # if you don't want all attributes of the draft to be saved on the live object.
      #
      # This is an array of attributes (including has_one association id columns) which will be saved 
      # on the object when its' draft is approved.
      #
      # For instance, if you want to omit updated_at, for whatever reason, you would define this in your model:
      #
      #  def approvable_attributes
      #    self.attributes.keys - ["created_at", "updated_at"]
      #  end
      #
      # WARNING: Don't include "created_at" if you don't want to modify this object's created_at!
      #
      # @return [Array] names of approvable attributes
      def approvable_attributes
        self.attributes.keys - ["created_at"]
      end
      #############################
      # END CONFIGURABLE METHODS
      #############################


      # Updates the approved version with any changes on the draft, and all the drafts' associated objects.
      # 
      # If the approved version changes_require_approval? returns false, this method exits early and does nothing
      # to the approved version.
      #
      # THE DRAFT VERSION IS DESTROYED IN THIS PROCESS. To generate a new draft, simply call <tt>editable_version</tt>
      # again on the approved object.
      # 
      # @return [ActiveRecord Object] updated version of the approved object
      def publish_draft!
        @live_version  = get_approved_version
        @draft_version = editable_version
        return unless changes_require_approval? && @draft_version.is_draft? # No-op. ie. the business is in a state that doesn't require approval.

        transaction do
          save_attribute_changes_and_has_one_assocations_from_draft
          update_has_many_associations_from_draft
          @live_version.draft.destroy # We have to do this since we moved all the draft's has_many associations to @live_version. If you call "editable_version" later, it'll build the draft.
        end
        @live_version = self.class.find(@live_version.id)
      end

      # Get the object's draft if changes require approval; this method creates one if it doesn't exist yet
      # If changes do not require approval, the original approved object is returned
      #
      # @return ActiveRecord Object
      def editable_version
        return get_approved_version unless changes_require_approval?
        is_draft? ? self : get_draft
      end

      # Get the approved version. Intended for use on a draft object, but works on a live/approved object too
      #
      # @return (ActiveRecord Object)
      def get_approved_version
        approved_version || self
      end

    protected #################################################################

      def get_draft
        draft || create_draft_version
      end

      def editable_association_names
        self.class.const_get(:DRAFT_EDITABLE_ASSOCIATIONS)
      end

    private ####################################################################

      def create_draft_version
        # Don't call this directly. Use editable_version instead.
        return draft if draft.present?
        dupe = amoeba_dup
        begin
          self.draft = dupe
          self.draft.save!(validate: false)
        rescue => e
          raise DraftCreationError, dupe.errors.full_messages.to_sentence
        end
        draft
      end

      def save_attribute_changes_and_has_one_assocations_from_draft
        @draft_version.attributes.each do |attribute, value|
        	next unless attribute.in? usable_approvable_attributes
          @live_version.send("#{attribute}=", value)
        end
        @live_version.save!
      end

      def update_has_many_associations_from_draft
        editable_association_names.each do |assoc|
          reflection = self.class.reflect_on_association(assoc)
          next unless reflection_is_has_many(reflection)

          @live_version.send(assoc).destroy_all

          attribute_updates = {}
          attribute_updates[reflection.foreign_key] = @live_version.id
          attribute_updates['updated_at']           = Time.now if reflection.klass.column_names.include?('updated_at')
          attribute_updates['approved_version_id']  = nil

          @draft_version.send(assoc).update_all attribute_updates
        end
      end

      def usable_approvable_attributes
      	approvable_attributes.map(&:to_s) - ['approved_version_id', 'id']
      end

      def association_is_has_many(name)
      	# Note when implementing for Rails 4, macro is renamed to something else
        self.class.reflect_on_association(name.to_sym).macro == :has_many
      end

      def reflection_is_has_many(reflection)
      	# Note when implementing for Rails 4, macro is renamed to something else
      	reflection.macro == :has_many
      end
    end

    module InstanceInterrogators
      # @return [Boolean] whether the current ActiveRecord object is a draft
      def is_draft?
        raise DraftPunk::ApprovedVersionIdError unless respond_to?("approved_version_id")
        approved_version_id.present?
      end

      # @return [Boolean] whether the current ActiveRecord object has a draft version
      def has_draft?
        raise DraftPunk::ApprovedVersionIdError unless respond_to?(:approved_version_id)
        draft.present?
      end
    end

  end
end