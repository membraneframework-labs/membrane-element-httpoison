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
  * mode - mode of operation, if it is `:push` it will generate buffers as fast
    as they are being received from the network (this is the default). If it is 
    `:pull` it will generate buffers if it receives Underrun Event on the `:source`
    pad.
  """

  defstruct location: nil, method: :get, body: "", headers: [], options: [], mode: :push

  @type location_t :: String.t
  @type method_t :: :get | :post | :put | :patch | :delete | :head | :options
  @type body_t :: HTTPoison.body
  @type headers_t :: HTTPoison.headers
  @type options_t :: Keyword.t
  @type mode_t :: :pull | :push

  @type t :: %Membrane.Element.HTTPoison.Source.Options{
    location: location_t,
    method: method_t,
    body: body_t,
    headers: headers_t,
    options: options_t,
    mode: mode_t,
  }
end
