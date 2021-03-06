# frozen_string_literal: true

module FCB
  class UploadZippedData
    TEST_API_PATH = 'http://www-test2.1cb.kz:80/DataPumpService/DataPumpService'.freeze
    PROD_API_PATH = 'https://secure.1cb.kz/DataPump/DataPumpService.asmx'.freeze

    REQUIRED_ARGS = [
      :funding_type, :credit_purpose_2, :credit_object, :real_payment_date, :classification, :collateral,
      :collateral_value, :collateral_currency, :collateral_type, :instalment_payment_method_id,
      :instalment_payment_period_id, :subject_role_id, :accounting_date,

      :operation_type, :contract_number, :contract_phase, :contract_status, :start_date, :end_date,
      :total_amount, :instalment_amount, :instalment_count, :outstanding_instalment_count, :outstanding_amount,
      :overdue_instalment_count, :overdue_amount,
      :first_name, :surname, :fathers_name, :gender, :subject_classification, :residency, :date_of_birth, :citizenship,
      :subject_iin, :subject_iin_system_registration_date,
      :subject_identity_document_number, :subject_identity_document_issued_on, :subject_identity_document_expire_on,
      :subject_identity_document_system_registration_date,
      :residential_address_locality, :residential_address_full,
      :registration_address_locality, :registration_address_full,
      :communication_type, :communication
    ].freeze

    def initialize(env: :production,
                   culture: 'ru-RU',
                   user_name:,
                   password:)
      @culture = culture
      @user_name = user_name
      @password = password
      @parser = Nori.new
      @env = env.to_sym
    end

    def call(args: {})
      missed_args = REQUIRED_ARGS - args.keys.map(&:to_sym)
      return M.Failure(missed_fields: missed_args) if missed_args.any?

      @params = args
      uri = URI(@env == :production ? PROD_API_PATH : TEST_API_PATH)
      request = Net::HTTP::Post.new(uri)
      request.body = make_request_xml
      request.content_type = 'text/xml; charset=utf-8'
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.port == 443
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if uri.port == 443
      response = http.start do |_|
        _.request(request)
      end
      parser = Nori.new
      hash = parser.parse(response.body)
      error = hash.dig('S:Envelope', 'S:Body', 'S:Fault')
      return M.Failure(:request_error) if error

      data = hash['S:Envelope']['S:Body']['UploadZippedData2Response']['UploadZippedData2Result']
      return M.Failure(:no_data) unless data

      M.Success(data)
    end

    private

    def make_request_xml
      xml = Builder::XmlMarkup.new(indent: 2)
      xml.instruct!(:xml, encoding: 'UTF-8')
      xml.soapenv(:Envelope,
                    'xmlns:soapenv' => 'http://schemas.xmlsoap.org/soap/envelope/',
                    'xmlns:ws' => 'https://ws.creditinfo.com') do
        xml.soapenv(:Header) do
          xml.ws(:CigWsHeader) do
            xml.ws :UserName, @user_name
            xml.ws :Password, @password
            xml.ws :Culture, @culture
          end
        end
        xml.soapenv(:Body) do
          xml.ws(:UploadZippedData2) do
            xml.ws :zippedXML, zippedXML_base64
            xml.ws :schemaId, 3
          end
        end
      end
    end

    def zippedXML_base64
      filename = 'zippedXML.zip'
      temp_file = Tempfile.new(filename)

      begin
        require 'zip'
        Zip::OutputStream.open(temp_file) { |zos| }

        # XML
        loan_user_xml = Tempfile.new('loan_user_xml').tap do |file|
          file.binmode
          file.write xml_body
          file.rewind
        end

        Zip::File.open(temp_file.path, Zip::File::CREATE) do |zip|
          zip.add('loan_user_xml.xml', loan_user_xml)
        end

        zip_data = File.read(temp_file.path)
        Base64.strict_encode64(zip_data)
      ensure
        # Close and delete the temp file
        temp_file.close
        temp_file.unlink
      end
    end

    def xml_body
      xml = Builder::XmlMarkup.new(indent: 2)
      xml.instruct!
      xml.Records(xmlns: 'http://www.datapump.cig.com', "xmlns:xs": 'http://www.w3.org/2001/XMLSchema-instance') do |a|
        a.Contract(operation: @operation_type) do |b|
          b.General do |c|
            c.ContractCode(@params[:contract_number])
            c.AgreementNumber(@params[:contract_number])
            c.FundingType(id: @params[:funding_type])
            c.CreditPurpose2(id: @params[:credit_purpose_2])
            c.CreditObject(id: @params[:credit_object])
            c.ContractPhase(id: @params[:contract_phase])
            c.ContractStatus(id: @params[:contract_status])
            c.StartDate(@params[:start_date])
            c.EndDate(@params[:end_date])
            c.RealPaymentDate(@params[:real_payment_date]) if @params[:real_payment_date]
            c.Classification(id: @params[:classification])
            c.Collaterals do |d|
              d.Collateral(typeId: @params[:collateral]) do |e|
                e.Value(@params[:collateral_value], currency: @params[:collateral_currency], typeId: @params[:collateral_type])
              end
            end
            c.Subjects do |f|
              f.Subject(roleId: @params[:subject_role_id]) do |g|
                g.Entity do |h|
                  h.Individual do |i|
                    i.FirstName do |j|
                      j.Text(@params[:first_name], language: 'ru-RU')
                    end
                    i.Surname do |j|
                      j.Text(@params[:surname], language: 'ru-RU')
                    end
                    i.FathersName do |j|
                      j.Text(@params[:fathers_name], language: 'ru-RU')
                    end
                    i.Gender(@params[:gender])
                    i.Classification(id: @params[:subject_classification])
                    i.Residency(id: @params[:residency])
                    i.DateOfBirth(@params[:date_of_birth])
                    i.Citizenship(id: @params[:citizenship])
                    i.Identifications do |j|
                      j.Identification(typeId: '14', rank: '1') do |k|
                        k.Number(@params[:subject_iin])
                        k.RegistrationDate(@params[:subject_iin_system_registration_date])
                      end
                      j.Identification(typeId: '7', rank: '1') do |k|
                        k.Number(@params[:subject_identity_document_number])
                        k.RegistrationDate(@params[:subject_identity_document_system_registration_date])
                        k.IssueDate(@params[:subject_identity_document_issued_on])
                        k.ExpirationDate(@params[:subject_identity_document_expire_on])
                      end
                    end
                    i.Addresses do |j|
                      j.Address(typeId: '1', katoId: @params[:residential_address_locality]) do |k|
                        k.StreetName do |l|
                          l.Text(@params[:residential_address_full], language: 'ru-RU')
                        end
                      end
                      j.Address(typeId: '6', katoId: @params[:registration_address_locality]) do |k|
                        k.StreetName do |l|
                          l.Text(@params[:registration_address_full], language: 'ru-RU')
                        end
                      end
                    end
                    i.Communications do |j|
                      j.Communication(@params[:communication], typeId: @params[:communication_type])
                    end
                  end
                end
              end
            end
          end
          b.Type do |c|
            c.Instalment(paymentMethodId: @params[:instalment_payment_method_id], paymentPeriodId: @params[:instalment_payment_period_id]) do |d|
              d.TotalAmount(@params[:total_amount], currency: 'KZT')
              d.InstalmentAmount(@params[:instalment_amount], currency: 'KZT')
              d.InstalmentCount(@params[:instalment_count])
              d.Records do |e|
                e.Record(accountingDate: @params[:accounting_date]) do |f|
                  f.OutstandingInstalmentCount(@params[:outstanding_instalment_count])
                  f.OutstandingAmount(@params[:outstanding_amount], currency: 'KZT')
                  f.OverdueInstalmentCount(@params[:overdue_instalment_count])
                  f.OverdueAmount(@params[:overdue_amount], currency: 'KZT')
                end
              end
            end
          end
        end
      end
    end
  end
end
