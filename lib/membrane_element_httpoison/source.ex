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
    IO.inspect location
    options = options |> Keyword.merge(stream_to: self(), async: :once)
    with {:ok, async_response} <-
      HTTPoison.request(method, location, body, headers, options)
    do {:ok, {[], %{state | async_response: async_response, streaming: true}}}
    else {:error, reason} -> {:error, {:httperror, reason}}
    end
  end

  @doc false
  def handle_demand(:source, size, _, %{streaming: true} = state) do
    IO.puts "http demand (streaming)"
    {:ok, {[], state |> Map.update!(:demand, & &1 + size)}}
  end

  @doc false
  def handle_demand(:source, size, _, state) do
    IO.puts "http demand"
    with {:ok, state} <- state |> Map.update!(:demand, & &1 + size) |> stream_next
    do
      IO.puts "streaming"
      {:ok, {[], state}}
    end
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: 200}, state) do
    debug("Got 200 OK")
    with {:ok, state} <- state |> stream_next,
    do: {:ok, {[], state}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncStatus{code: code}, _state) do
    warn("Got unexpected status code #{code}")
    {:error, {:code, code}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, state) do
    debug("Got headers #{inspect(headers)}")
    with {:ok, state} <- state |> stream_next,
    do: {:ok, {[], state}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncChunk{chunk: chunk}, state) do
    debug("Got chunk #{inspect(chunk)}")

    with {:ok, state} <- state |> Map.update!(:demand, & &1 - 1) |> stream_next,
    do: {:ok, {[buffer: {:source, %Buffer{payload: chunk}}], state}}
  end


  @doc false
  def handle_other(%HTTPoison.AsyncEnd{}, state) do
    debug("End of stream")

    {:ok, {[event: {:source, Event.eos()}], %{state | streaming: false}}}
  end

  @doc false
  def handle_other(%HTTPoison.AsyncRedirect{headers: headers}, state) do
    case headers |> List.keyfind("Location", 0) do
      {"Location", new_location} ->
        debug("Redirect to #{new_location}")

      _ ->
        warn("Got redirect but without specyfying location")
    end

    {:ok, {[], state}}
  end

  defp stream_next(%{demand: demand} = state)
  when demand <= 0
  do {:ok, %{state | streaming: false}}
  end

  defp stream_next(%{demand: demand, async_response: resp} = state)
  when demand > 0
  do
    with {:ok, resp} <- resp |> HTTPoison.stream_next
    do {:ok, %{state | streaming: true, async_response: resp}}
    else {:error, reason} -> warn_error "Http stream_next/1 error", reason
    end
  end
end
