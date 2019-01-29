defmodule Membrane.Element.HTTPoison.Source do
  @moduledoc """
  This module provides a source element allowing you to receive data as a client
  using HTTP. It is based upon [HTTPoison](https://github.com/edgurgel/httpoison)
  library that is responsible for making HTTP requests.

  See the `t:t/0` for the available configuration options.
  """
  use Membrane.Element.Base.Source
  use Membrane.Log, tags: :membrane_element_httpoison
  alias Membrane.{Buffer, Event, Element, Time}
  import Mockery.Macro

  def_output_pads output: [caps: :any]

  def_options location: [
                type: :string,
                description: "The URL to fetch by the element"
              ],
              method: [
                type: :atom,
                spec: :get | :post | :put | :patch | :delete | :head | :options,
                description: "HTTP method that will be used when making a request",
                default: :get
              ],
              body: [
                type: :string,
                description: "The request body",
                default: ""
              ],
              headers: [
                type: :keyword,
                spec: HTTPoison.headers(),
                description:
                  "List of additional request headers in format accepted by `HTTPoison.request/5`",
                default: []
              ],
              poison_opts: [
                type: :keyword,
                description:
                  "Additional options for HTTPoison in format accepted by `HTTPoison.request/5`",
                default: []
              ],
              max_retries: [
                type: :integer,
                spec: non_neg_integer() | :infinity,
                description: """
                Maximum number of retries before returning an error. Can be set to `:infinity`.
                """,
                default: 0
              ],
              retry_delay: [
                type: :time,
                description: """
                Delay before another retry after error.
                """,
                default: 200 |> Time.millisecond()
              ],
              is_live: [
                type: :boolean,
                description: """
                Assume the source is live. If true, when resuming after error,
                the element will not use `Range` header to skip to the
                current position in bytes.
                """,
                default: false
              ]

  @impl true
  def handle_init(%__MODULE__{} = options) do
    state =
      options
      |> Map.merge(%{
        async_response: nil,
        retries: 0,
        streaming: false,
        pos_counter: 0
      })

    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, %{async_response: response} = state) do
    state =
      if response != nil do
        state |> close_request()
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    state |> connect
  end

  @impl true
  def handle_demand(:output, _size, _unit, _ctx, %{streaming: true} = state) do
    # We have already requested next frame (using HTTPoison.stream_next())
    # so we do nothinig
    {:ok, state}
  end

  def handle_demand(:output, _size, _unit, _ctx, %{async_response: nil} = state) do
    # We're waiting for reconnect
    {:ok, state}
  end

  def handle_demand(:output, _size, _unit, _ctx, state) do
    debug("HTTPoison: requesting next chunk")

    with {:ok, resp} <- state.async_response |> mockable(HTTPoison).stream_next() do
      {:ok, %{state | async_response: resp, streaming: true}}
    else
      {:error, reason} ->
        warn("HTTPoison.stream_next/1 error: #{inspect(reason)}")

        retry({:stream_next, reason}, state |> close_request(), false)
    end
  end

  @impl true
  def handle_other(%struct{id: msg_id} = msg, _ctx, %{async_response: %{id: id}} = state)
      when msg_id != id and
             struct in [
               HTTPoison.AsyncChunk,
               HTTPoison.AsyncEnd,
               HTTPoison.AsyncHeaders,
               HTTPoison.AsyncRedirect,
               HTTPoison.AsyncStatus,
               HTTPoison.Error
             ] do
    warn(
      "Ignoring message #{inspect(msg)} because it does not match current response id: #{
        inspect(id)
      }"
    )

    {:ok, state}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: 200}, _ctx, state) do
    debug("HTTPoison: Got 200 OK")
    {{:ok, redemand: :output}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: 206}, _ctx, state) do
    debug("HTTPoison: Got 206 Partial Content")
    {{:ok, redemand: :output}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: code}, _ctx, state)
      when code in [301, 302] do
    warn("""
    Got #{inspect(code)} status indicating redirection.
    If you want to follow add `follow_redirect: true` to :poison_opts
    """)

    retry({:httpoison, :redirect}, state |> close_request())
  end

  def handle_other(%HTTPoison.AsyncStatus{code: 416}, _ctx, state) do
    warn("HTTPoison: Got 416 Invalid Range (pos_counter is #{inspect(state.pos_counter)})")
    retry({:httpoison, :invalid_range}, state |> close_request())
  end

  def handle_other(%HTTPoison.AsyncStatus{code: code}, _ctx, state) do
    warn("HTTPoison: Got unexpected status code #{code}")
    retry({:http_code, code}, state |> close_request())
  end

  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, _ctx, state) do
    debug("HTTPoison: Got headers #{inspect(headers)}")

    {{:ok, redemand: :output}, %{state | streaming: false}}
  end

  def handle_other(
        %HTTPoison.AsyncChunk{chunk: chunk},
        %Ctx.Other{playback_state: :playing},
        state
      ) do
    state =
      state
      |> Map.update!(:pos_counter, &(&1 + byte_size(chunk)))

    actions = [buffer: {:output, %Buffer{payload: chunk}}, redemand: :output]
    {{:ok, actions}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncChunk{}, _ctx, state) do
    # We received chunk after we've stopped playing. We'll ignore that data.
    {:ok, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncEnd{}, _ctx, state) do
    info("HTTPoison EOS")
    new_state = %{state | streaming: false, async_response: nil}
    {{:ok, event: {:output, %Event.EndOfStream{}}}, new_state}
  end

  def handle_other(%HTTPoison.Error{reason: reason}, _ctx, state) do
    warn("HTTPoison error #{inspect(reason)}")

    retry({:httpoison, reason}, state |> close_request(), false)
  end

  def handle_other(%HTTPoison.AsyncRedirect{to: new_location}, _ctx, state) do
    debug("HTTPoison: redirecting to #{new_location}")

    %{state | location: new_location, streaming: false}
    |> connect
  end

  def handle_other(:reconnect, _ctx, state) do
    state |> connect()
  end

  @spec retry(reason :: any(), state :: Element.state_t(), delay? :: boolean) ::
          {:ok, Element.state_t()}
  defp retry(reason, state, delay? \\ true)

  defp retry(reason, %{retries: retries, max_retries: max_retries} = state, _delay)
       when retries >= max_retries do
    {{:error, reason}, state}
  end

  defp retry(_reason, state, false) do
    connect(%{state | retries: state.retries + 1})
  end

  defp retry(_reason, %{retry_delay: delay, retries: retries} = state, true) do
    Process.send_after(self(), :reconnect, delay |> Time.to_milliseconds())
    {:ok, %{state | retries: retries + 1}}
  end

  defp connect(state) do
    %{
      method: method,
      location: location,
      body: body,
      headers: headers,
      poison_opts: opts,
      pos_counter: pos,
      is_live: is_live
    } = state

    opts = opts |> Keyword.merge(stream_to: self(), async: :once)

    headers =
      if pos > 0 and not is_live do
        [{"Range", "bytes=#{pos}-"} | headers]
      else
        headers
      end

    debug("HTTPoison: connecting, request: #{inspect({method, location, body, headers, opts})}")

    with {:ok, async_response} <-
           mockable(HTTPoison).request(method, location, body, headers, opts) do
      {:ok, %{state | async_response: async_response, streaming: true}}
    else
      {:error, reason} -> retry({:httpoison, reason}, state)
    end
  end

  defp close_request(%{async_response: nil} = state) do
    %{state | streaming: false}
  end

  defp close_request(%{async_response: resp} = state) do
    mockable(:hackney).close(resp.id)
    %{state | async_response: nil, streaming: false}
  end
end
