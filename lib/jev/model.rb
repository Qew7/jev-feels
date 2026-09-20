# frozen_string_literal: true

module Jev
  module Model
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def inherited(subclass)
        super
        subclass.extend ClassMethods
      end

      def feels(attribute, name, description)
        raise ArgumentError, "attribute must be a Symbol" unless attribute.is_a?(Symbol)

        Jev.define(self, name, description)
        (@jev_feels_attributes ||= {})[name.to_sym] = attribute
      end

      def jev_feels_attribute(name)
        current = self
        while current && current != Object
          found = current.instance_variable_get(:@jev_feels_attributes)&.[](name)
          return found if found

          current = current.superclass
        end
      end
    end

    def feels(predicate)
      Jev.feels(jev_text_for(predicate), self.class, predicate)
    end

    def feels?(predicate, threshold: Jev.configuration.threshold)
      Jev.feels?(jev_text_for(predicate), self.class, predicate, threshold: threshold)
    end

    private

    def jev_text_for(predicate)
      attribute = self.class.jev_feels_attribute(predicate.to_sym) || raise(
        UndefinedDefinition, "Undefined Jev definition: #{predicate.inspect} for #{self.class}"
      )

      public_send(attribute).to_s
    end
  end
end
