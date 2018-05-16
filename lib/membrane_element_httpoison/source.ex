defmodule Membrane.Element.HTTPoison.Source do
  use Membrane.Element.Base.Source
  use Membrane.Mixins.Log, tags: :membrane_element_httpoison
  alias Membrane.{Buffer, Event}

  def_known_source_pads source: {:always, :pull, :any}

  def_options location: [
                type: :string,
                description: "The URL to fetch by the element"
              ],
              method: [
                type: :atom,
                spec: :get | :post | :put | :patch | :delete | :head | :options,
                description: "HTTP method to use",
                default: :get
              ],
              body: [
                type: :string,
                description: "Request body",
                default: ""
              ],
              headers: [
                type: :keyword,
                spec: HTTPoison.headers(),
                description:
                  "List of additional request headers in format accepted by `HTTPoison.request/5`",
                default: []
              ],
              options: [
                type: :keyword,
                description:
                  "Additional options to HTTPoison in format accepted by `HTTPoison.request/5`",
                default: []
              ],
              resume_on_error: [
                type: :boolean,
                description: """
                If set to true, the element will try to automatically resume the download (from proper position)
                if the connection is broken.
                """,
                default: false
              ],
              is_live: [
                type: :boolean,
                description: """
                Assume the source is live. When true, resume after error will not use `Range`
                header to skip to the current position (in bytes).
                """,
                default: false
              ]

  @impl true
  def handle_init(%__MODULE__{} = options) do
    state =
      options
      |> Map.merge(%{
        async_response: nil,
        streaming: false,
        pos_counter: 0,
        playing: false
      })

    {:ok, state}
  end

  @impl true
  def handle_prepare(:playing, %{async_response: response} = state) do
    # transition from :playing to :prepared
    if response != nil do
      :hackney.close(response.id)
    end
    {:ok, %{state | playing: false, async_response: nil}}
  end

  def handle_prepare(_, state), do: {:ok, state}

  @impl true
  def handle_play(state) do
    %{state | playing: true} |> connect
  end

  @impl true
  def handle_demand(:source, _, _, _, %{streaming: true} = state) do
    # We have already requested next frame (using HTTPoison.stream_next())
    # so we do nothinig
    {:ok, state}
  end

  def handle_demand(:source, _, _, _, state) do
    debug("HTTPoison: requesting next chunk")

    with {:ok, resp} <- state.async_response |> HTTPoison.stream_next() do
      {:ok, %{state | async_response: resp, streaming: true}}
    else
      {:error, reason} ->
        warn_error("Http stream_next/1 error", {:stream_next, reason})

        if state.resume_on_error do
          %{state | streaming: false} |> connect(true)
        else
          {{:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_other(%struct{id: msg_id} = msg, %{async_response: %{id: id}} = state)
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

  def handle_other(%HTTPoison.AsyncStatus{code: 200}, state) do
    debug("HTTPoison: Got 200 OK")
    {{:ok, redemand: :source}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: 206}, state) do
    debug("HTTPoison: Got 206 Partial Content")
    {{:ok, redemand: :source}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: 416, id: id}, state) do
    warn("HTTPoison: Got 416 Invalid Range")
    :hackney.close(id)
    {{:error, "Failed to make range request"}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncStatus{code: code, id: id}, state) do
    warn("HTTPoison: Got unexpected status code #{code}")
    :hackney.close(id)
    {{:error, {:http_code, code}}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, state) do
    debug("HTTPoison: Got headers #{inspect(headers)}")

    {{:ok, redemand: :source}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncChunk{}, %{playing: false} = state) do
    # We received chunk after we stopped playing. We'll ignore that data.
    {:ok, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncChunk{chunk: chunk}, state) do
    state =
      state
      |> Map.update!(:pos_counter, &(&1 + byte_size(chunk)))

    actions = [buffer: {:source, %Buffer{payload: chunk}}, redemand: :source]
    {{:ok, actions}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.AsyncEnd{}, state) do
    info("HTTPoison EOS")
    {{:ok, event: {:source, Event.eos()}}, %{state | streaming: false}}
  end

  def handle_other(%HTTPoison.Error{reason: reason}, %{resume_on_error: resume} = state) do
    warn("HTTPoison error #{inspect(reason)}")

    if resume do
      state |> connect(true)
    else
      {{:error, {:httpoison, reason}}, %{state | streaming: false}}
    end
  end

  def handle_other(%HTTPoison.AsyncRedirect{headers: headers}, state) do
    with {"Location", new_location} <- headers |> List.keyfind("Location", 0, :no_location) do
      debug("HTTPoison: redirecting to #{new_location}")
    else
      :no_location -> warn("HTTPoison: got redirect but without specyfying location")
    end

    {{:ok, redemand: :source}, %{state | streaming: false}}
  end

  defp connect(state, reconnect \\ false) do
    %{
      method: method,
      location: location,
      body: body,
      headers: headers,
      options: options,
      pos_counter: pos,
      is_live: is_live
    } = state

    options = options |> Keyword.merge(stream_to: self(), async: :once)

    headers =
      if reconnect and is_live do
        [{"Range", "bytes=#{pos}-"} | headers]
      else
        headers
      end

    debug(
      "HTTPoison: connecting, request: #{inspect({method, location, body, headers, options})}"
    )

    with {:ok, async_response} <- HTTPoison.request(method, location, body, headers, options) do
      {:ok, %{state | async_response: async_response, streaming: true}}
    else
      {:error, reason} -> {{:error, {:httpoison, reason}}, state}
    end
  end
end
