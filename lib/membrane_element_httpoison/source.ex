defmodule Membrane.Element.HTTPoison.Source do
  use Membrane.Element.Base.Source
  use Membrane.Mixins.Log, tags: :membrane_element_httpoison
  alias __MODULE__.Options
  alias Membrane.{Buffer, Event}



  def_known_source_pads %{
    source: {:always, :pull, :any}
  }

  def_options %{
    location: [
      type: :string,
      description: "The URL to fetch by the element",
      required: true,
      regex: ~r[^(http|https)://.+$],
    ],
    method: [
      type: :atom,
      description: "HTTP method to use",
      required: true,
      default: :get,
      enum: ~w[get post put patch delete head options]a,
    ],
    body: [
      type: :string,
      description: "Request body",
      required: false,
      default: "",
    ],
    headers: [
      type: :keyword,
      description: "List of additional request headers in format accepted by `HTTPoison.request/5`",
      required: false,
      default: [],
    ],
    options: [
      type: :keyword,
      description: "Additional options to HTTPoison in format accepted by `HTTPoison.request/5`",
      required: false,
      default: [],
    ],
  }


  # Private API

  @doc false
  def handle_init(%Options{method: method, location: location, headers: headers, body: body, options: options}) do
    {:ok, %{
      location: location,
      method: method,
      headers: headers,
      body: body,
      options: options,
      async_response: nil,
      streaming: false,
      demand: 0,
      type: nil,
      pos_counter: 0,
      playing: false,
    }}
  end


  @doc false
  def handle_play(state) do
    %{state | playing: true} |> connect
  end

  @doc false
  def handle_prepare(:playing, state) do
    {:ok, %{state | playing: false}}
  end

  @doc false
  def handle_prepare(_, state), do: {:ok, state}

  @doc false
  def handle_demand(:source, size, type, _, %{demand: demand, streaming: true} = state)
  when type in [:buffers, :bytes] do
    {:ok, %{state | demand: demand + size, type: type}}
  end

  @doc false
  def handle_demand(:source, size, type, _, %{demand: demand} = state)
  when type in [:buffers, :bytes] do
    state = %{state | demand: demand + size, type: type}
    {:ok, state |> stream_next}
  end

  @doc false
  def handle_other(%struct{id: msg_id} = msg, %{async_response: %{id: id}} = state)
  when msg_id != id
  and struct in [
      HTTPoison.AsyncChunk, HTTPoison.AsyncEnd, HTTPoison.AsyncHeaders,
      HTTPoison.AsyncRedirect, HTTPoison.AsyncStatus, HTTPoison.Error,
    ]
  do
    warn "Ignoring message #{inspect msg} because it does not match current response id: #{inspect id}"
    {:ok, state}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: 200}, state) do
    debug "HTTPoison: Got 200 OK"
    {:ok, state |> stream_next}
  end

 @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: 206}, state) do
    debug "HTTPoison: Got 206 Partial Content"
    {:ok, state |> stream_next}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: 416}, state) do
   warn "HTTPoison: Got 416 Invalid Range"
   {{:ok, event: {:source, Event.eos}}, %{state | streaming: false}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: code}, state) do
    warn "HTTPoison: Got unexpected status code #{code}"
    {{:error, {:http_code, code}}, state}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, state) do
    debug "HTTPoison: Got headers #{inspect(headers)}"
    {:ok, state |> stream_next}
  end

  def handle_other(%HTTPoison.AsyncChunk{}, %{playing: false} = state) do
    {:ok, %{state | streaming: false}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncChunk{chunk: chunk}, %{type: type} = state) do
    demand_update = case type do
      :buffers -> & &1 - 1
      :bytes   -> & &1 - byte_size(chunk) |> max(0)
    end

    state = state
      |> Map.update!(:pos_counter, & &1 + byte_size(chunk))
      |> Map.update!(:demand, demand_update)

    {{:ok, buffer: {:source, %Buffer{payload: chunk}}}, state |> stream_next}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncEnd{}, state) do
    info "HTTPoison EOS"
    {{:ok, event: {:source, Event.eos}}, %{state | streaming: false}}
  end

  @doc false
  def handle_other(%HTTPoison.Error{reason: reason}, state) do
    warn("Error #{inspect(reason)}")
    state |> connect
  end

  @doc false
  def handle_other(%HTTPoison.AsyncRedirect{headers: headers}, state) do
    with {"Location", new_location} <- headers |> List.keyfind("Location", 0, :no_location)
    do
      debug "HTTPoison: redirecting to #{new_location}"
    else
      :no_location -> warn "HTTPoison: got redirect but without specyfying location"
    end
    {:ok, state |> stream_next}
  end

  def handle_other(:httpoison_stream_next, state) do
    debug "HTTPoison: requesting next chunk"
    with {:ok, resp} <- state.async_response |> HTTPoison.stream_next
    do {:ok, %{state | async_response: resp}}
    else {:error, reason} ->
      warn_error("Http stream_next/1 error", {:stream_next, reason})
      %{state | streaming: false} |> connect
    end
  end

  defp stream_next(%{demand: demand, playing: playing} = state)
  when demand <= 0 or not playing
  do %{state | streaming: false}
  end

  defp stream_next(%{demand: demand} = state)
  when demand > 0
  do
    send self(), :httpoison_stream_next
    %{state | streaming: true}
  end

  defp connect(%{method: method, location: location, body: body, headers: headers, options: options, pos_counter: pos} = state) do
    options = options |> Keyword.merge(stream_to: self(), async: :once)
    headers = [{"Range", "bytes=#{pos}-"} | headers]
    debug "HTTPoison: connecting, request: #{inspect {method, location, body, headers, options}}"
    with {:ok, async_response} <-
      HTTPoison.request(method, location, body, headers, options)
    do {:ok, %{state | async_response: async_response, streaming: true}}
    else {:error, reason} -> {{:error, {:httperror, reason}}, state}
    end
  end

end
