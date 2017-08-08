defmodule Membrane.Element.HTTPoison.Source.Options do
  @moduledoc """
  Structure representing options that can be passed to
  `Membrane.Element.HTTPoison.Source` element.

  It contains the following fields:

  * location - URL to fetch,
  * method - HTTP method to use, can be one of `:get`, `:post`, `:put`, `:patch`,
    `:delete`, `:head` or `:options`; `:get` by default,
  * body - request body, in the same form as passed to `HTTPoison.request/5`,
    empty string by default,
  * headers - request headers, in the same form as passed to `HTTPoison.request/5`,
    empty list by default,
  * options - request options, in the same form as passed to `HTTPoison.request/5`,
    empty list by default. Please do not use `:stream_to` option here,
  """

  defstruct location: nil, method: :get, body: "", headers: [], options: []

  @type location_t :: String.t
  @type method_t :: :get | :post | :put | :patch | :delete | :head | :options
  @type body_t :: HTTPoison.body
  @type headers_t :: HTTPoison.headers
  @type options_t :: Keyword.t

  @type t :: %Membrane.Element.HTTPoison.Source.Options{
    location: location_t,
    method: method_t,
    body: body_t,
    headers: headers_t,
    options: options_t,
  }
end
