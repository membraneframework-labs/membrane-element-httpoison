defmodule Membrane.Element.HTTPoison.Source do
  use Membrane.Element.Base.Source
  use Membrane.Mixins.Log
  alias __MODULE__.Options
  alias Membrane.{Buffer, Event}



  def_known_source_pads %{
    :source => {:always, :pull, :any}
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
    }}
  end


  @doc false
  def handle_play(%{method: method, location: location, body: body, headers: headers, options: options} = state) do
    options = options |> Keyword.merge(stream_to: self(), async: :once)
    with {:ok, async_response} <-
      HTTPoison.request(method, location, body, headers, options)
    do {:ok, %{state | async_response: async_response, streaming: true}}
    else {:error, reason} -> {{:error, {:httperror, reason}}, state}
    end
  end

  @doc false
  def handle_demand(:source, size, :buffers, _, %{streaming: true} = state) do
    {:ok, state |> Map.update!(:demand, & &1 + size)}
  end

  @doc false
  def handle_demand(:source, size, :buffers, _, state) do
    with {:ok, state} <- state |> Map.update!(:demand, & &1 + size) |> stream_next,
    do: {:ok, state},
    else: ({:error, reason} -> {{:error, reason}, state})
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: 200}, state) do
    debug "HTTPoison: Got 200 OK"
    with {:ok, state} <- state |> stream_next,
    do: {:ok, state},
    else: ({:error, reason} -> {{:error, reason}, state})
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: code}, state) do
    warn "HTTPoison: Got unexpected status code #{code}"
    {{:error, {:http_code, code}}, state}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, state) do
    debug "HTTPoison: Got headers #{inspect(headers)}"
    with {:ok, state} <- state |> stream_next,
    do: {:ok, state},
    else: ({:error, reason} -> {{:error, reason}, state})
  end

  @doc false
  def handle_other(%HTTPoison.AsyncChunk{chunk: chunk}, state) do
    debug "HTTPoison: Got chunk #{inspect(chunk)}"

    with {:ok, state} <- state |> Map.update!(:demand, & &1 - 1) |> stream_next,
    do: {{:ok, buffer: {:source, %Buffer{payload: chunk}}}, state},
    else: ({:error, reason} -> {{:error, reason}, state})
  end


  @doc false
  def handle_other(%HTTPoison.AsyncEnd{}, state) do
    debug("End of stream")
    warn "HTTPoison EOS"
    {{:ok, event: {:source, Event.eos}}, %{state | streaming: false}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncRedirect{headers: headers}, state) do
    with {"Location", new_location} <- headers |> List.keyfind("Location", 0, :no_location)
    do
      debug "HTTPoison: redirecting to #{new_location}"
    else
      :no_location -> warn "HTTPoison: got redirect but without specyfying location"
    end
    with {:ok, state} <- state |> stream_next,
    do: {:ok, state},
    else: ({:error, reason} -> {{:error, reason}, state})
  end

  defp stream_next(%{demand: demand} = state)
  when demand <= 0
  do {:ok, %{state | streaming: false}}
  end

  defp stream_next(%{demand: demand, async_response: resp} = state)
  when demand > 0
  do
    debug "HTTPoison: requesting next chunk"
    with {:ok, resp} <- resp |> HTTPoison.stream_next
    do {:ok, %{state | streaming: true, async_response: resp}}
    else {:error, reason} -> warn_error "Http stream_next/1 error", {:stream_next, reason}
    end
  end
end
