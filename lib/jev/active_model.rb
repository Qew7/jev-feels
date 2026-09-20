# frozen_string_literal: true

module Jev
  module ActiveModel
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def validates_feeling(attribute, predicate, message: nil, threshold: nil, at_least: nil, **options)
        feeling = { predicate: predicate, message: message, threshold: threshold, at_least: at_least }
        validates_each(attribute, **options) do |record, attr, value|
          Jev::ActiveModel.validate(record, attr, value, feeling)
        end
      end
    end

    def self.validate(record, attr, value, feeling)
      text = value.is_a?(String) ? value : value.to_s
      kwargs = feeling.slice(:threshold, :at_least).compact
      return if Jev.feels?(text, feeling[:predicate], **kwargs) == true

      record.errors.add(attr, feeling[:message] || "is not #{feeling[:predicate]}")
    end
  end
end

if defined?(ActiveModel::Validations::HelperMethods)
  ActiveModel::Validations::HelperMethods.include(Jev::ActiveModel::ClassMethods)
end
