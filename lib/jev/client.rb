# frozen_string_literal: true

module Jev
  class Client
    QUESTION_ID = "feels"
    MODEL = "jev-latest"

    def initialize(configuration)
      @configuration = configuration
    end

    def probability(text, instructions)
      extract_noul(transport.call(payload(text, instructions)))
    end

    private

    def transport
      @configuration.transport || Transport.new(@configuration)
    end

    def payload(text, instructions)
      {
        "model" => MODEL,
        "state" => text,
        "questions" => {
          QUESTION_ID => {
            "type" => "noul",
            "instructions" => instructions
          }
        }
      }
    end

    def extract_noul(body)
      raise InvalidResponseError, "Jev response is not a JSON object" unless body.is_a?(Hash)

      answers = body["answers"]
      raise InvalidResponseError, "Jev response is missing answers" unless answers.is_a?(Hash)

      answer = answers[QUESTION_ID]
      raise InvalidResponseError, "Jev response is missing the feels answer" unless answer.is_a?(Hash)

      noul = answer["noul"]
      raise InvalidResponseError, "Jev response is missing a noul probability" unless noul.is_a?(Numeric)

      noul = Float(noul)
      raise InvalidResponseError, "Jev noul probability is not finite" unless noul.finite?

      # ponytail: clamp out-of-range noul; raise if Jev starts returning uncalibrated values
      noul.clamp(0.0, 1.0)
    end
  end
end
