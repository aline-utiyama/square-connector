require 'httparty'
require 'json'
require 'uri'
require 'net/http'
require 'openssl'
require 'date'

def lambda_handler(event:, context:)
  
  # Sample pure Lambda function

  # Parameters
  # ----------
  # event: Hash, required
  #     API Gateway Lambda Proxy Input Format
  #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

  # context: object, required
  #     Lambda Context runtime methods and attributes
  #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

  # Returns
  # ------
  # API Gateway Lambda Proxy Output Format: dict
  #     'statusCode' and 'body' are required
  #     # api-gateway-simple-proxy-for-lambda-output-format
  #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html

  #  begin
  #    response = HTTParty.get('http://checkip.amazonaws.com/')
  #  rescue HTTParty::Error => error
  #    puts error.inspect
  #    raise error
  #  end

   @bm_key = "Bearer #{ENV['BM_KEY']}"
   @square_api_key = "Bearer #{ENV['SQUARE_KEY']}"
         
  if !event['body'].nil?
    body = JSON.parse(event['body'])
    puts body
    puts body['type']

    case body['type']
    when 'customer.created'
      customer_created(body)
    when 'customer.updated'
      customer_updated(body)
    when 'customer.deleted'
      customer_deleted(body)
    end
  end
  
  { statusCode: 200, body: JSON.generate('Ok') }
end

def customer_created(body)
  customer = body['data']['object']['customer']
  name = "#{customer['given_name']} #{customer['family_name']}"
  email = customer['email_address']
  oid = customer['id']
  created = customer['created_at']
  created_at = Date.parse(created)
  
  puts "Creating"
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/customers")
  
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Post.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"created\":\"#{created_at.to_time.to_i}\",\"oid\":\"#{oid}\",\"name\":\"#{name}\",\"email\":\"#{email}\"}"
  
  response = http.request(request)
  puts response.read_body
  puts "I am created"
end

def customer_updated(body)
  customer = body['data']['object']['customer']
  name = "#{customer['given_name']} #{customer['family_name']}"
  email = customer['email_address']
  oid = customer['id']
  created = customer['created_at']
  created_at = Date.parse(created)
  
  puts "Updating..."
  
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/customers/#{oid}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Put.new(url)
  request["Accept"] = 'application/json'
  request["Content-Type"] = 'application/json'
  request["Authorization"] = @bm_key
  request.body = "{\"name\":\"#{name}\",\"email\":\"#{email}\",\"created\":\"#{created_at.to_time.to_i}\"}"

  response = http.request(request)
  puts response.read_body

  if response.is_a?(Net::HTTPNotFound)
    customer_created(body)
  end
end

def customer_deleted(body)
  customer = body['data']['object']['customer']
  oid = customer['id']
  
  puts "Deleting..."
  url = URI("https://api.baremetrics.com/v1/82145757-9f4b-46e3-b67b-0bbf8632d0dd/customers/#{oid}")

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  
  request = Net::HTTP::Delete.new(url)
  request["Accept"] = 'application/json'
  request["Authorization"] = @bm_key
  
  response = http.request(request)
  puts response.read_body
  puts " I was deleted"
end
