# frozen_string_literal: true

module Jev
  class Client
    QUESTION_ID = "feels"
    MODEL = "jev-latest"

    def initialize(configuration)
      @configuration = configuration
    end

    def ask(text, questions)
      body = transport.call(payload(text, questions))
      parse(body, questions)
    end

    def probability(text, instructions)
      definition = Definition.build(name: :feels, instructions: instructions)
      ask(text, { QUESTION_ID => definition }).fetch(QUESTION_ID).probability
    end

    private

    def transport
      Harness.current_transport(@configuration)
    end

    def payload(text, questions)
      {
        "model" => MODEL,
        "state" => text,
        "questions" => questions.to_h { |id, definition| [id, definition.to_question] }
      }
    end

    def parse(body, questions)
      raise InvalidResponseError, "Jev response is not a JSON object" unless body.is_a?(Hash)

      answers = body["answers"]
      raise InvalidResponseError, "Jev response is missing answers" unless answers.is_a?(Hash)

      questions.to_h do |id, definition|
        answer = answers[id]
        raise InvalidResponseError, "Jev response is missing the #{id} answer" unless answer.is_a?(Hash)

        [id, Result.parse(answer, definition)]
      end
    end
  end
end
