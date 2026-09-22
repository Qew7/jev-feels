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

      def feels(attribute, name, description = nil, **options)
        declare_jev(attribute, name, description, options)
      end

      def decide(attribute, name, description = nil, **options)
        declare_jev(attribute, name, description, options)
      end

      def score(attribute, name, description = nil, **options)
        declare_jev(attribute, name, description, options)
      end

      def bind_jev_attribute(attribute, name)
        raise ArgumentError, "attribute must be a Symbol" unless attribute.is_a?(Symbol)

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

      def jev_bound_fields
        ancestors = []
        current = self
        while current && current != Object
          parent_bindings = current.instance_variable_get(:@jev_feels_attributes)
          ancestors << parent_bindings if parent_bindings
          current = current.superclass
        end
        bindings = {}
        ancestors.reverse_each { |parent_bindings| bindings.merge!(parent_bindings) }
        bindings.values.uniq
      end

      private

      def declare_jev(attribute, name, description, options)
        bind_jev_attribute(attribute, name)
        return if description.nil? && options.empty?

        Jev.define(self, name, description, **options)
      end
    end

    def feels(predicate)
      Jev.feels(jev_text_for(predicate), self.class, predicate)
    end

    def feels?(predicate, **)
      Jev.feels?(jev_text_for(predicate), self.class, predicate, **)
    end

    def decide(predicate, **)
      Jev.decide(jev_text_for(predicate), self.class, predicate, **)
    end

    def score(predicate, **)
      Jev.score(jev_text_for(predicate), self.class, predicate, **)
    end

    def measure(predicate = nil, **, &)
      if block_given?
        Jev.measure(jev_batch_text, self.class, **, &)
      else
        raise ArgumentError, "question is required" if predicate.nil?

        Jev.measure(jev_text_for(predicate), self.class, predicate, **)
      end
    end

    def match(predicate, **, &)
      Jev.match(jev_text_for(predicate), self.class, predicate, **, &)
    end

    private

    def jev_text_for(predicate)
      attribute = self.class.jev_feels_attribute(predicate.to_sym) || raise(
        UndefinedDefinition, "Undefined Jev definition: #{predicate.inspect} for #{self.class}"
      )

      public_send(attribute).to_s
    end

    def jev_batch_text
      fields = self.class.jev_bound_fields
      raise ArgumentError, "no Jev field is bound for #{self.class}" if fields.empty?
      raise ArgumentError, "measure block needs one field, got #{fields.inspect}" if fields.size > 1

      public_send(fields.first).to_s
    end
  end
end
