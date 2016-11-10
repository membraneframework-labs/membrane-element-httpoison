defmodule Membrane.Element.HTTP.SourceOptions do
  defstruct location: nil

  @type t :: %Membrane.Element.HTTP.SourceOptions{
    location: String.t
  }
end


defmodule Membrane.Element.HTTP.Source do
  use Membrane.Element.Base.Source
  alias Membrane.Element.HTTP.SourceOptions


  def handle_prepare(%SourceOptions{location: location}) do
    {:ok, %{
      location: location,
      content_type: "application/octet-stream"
    }}
  end


  @doc """
  Callback invoked when we receive command to start playing.

  It starts asynchronous request to the given location.
  """
  def handle_play(%{location: location} = state) do
    case HTTPoison.get(location, %{}, stream_to: self()) do
      {:ok, _ref} ->
        {:ok, state}

      {:error, reason} ->
        {:error, {:httperror, reason}}
    end
  end


  @doc """
  Callback invoked when we receive status code 200, which is fine.
  """
  def handle_other(%HTTPoison.AsyncStatus{code: 200}, state) do
    debug("Got 200 OK")
    {:ok, state}
  end


  @doc """
  Callback invoked when we receive status code other than 200, indicating error.
  """
  def handle_other(%HTTPoison.AsyncStatus{code: code}, state) do
    warn("Got unexpected status code #{code}")
    {:error, {:code, code}, state}
  end


  @doc """
  Callback invoked when we receive response headers from the server.

  Look for Content-Type header, and if it is present, save it so buffers we
  produce have valid content type set.
  """
  def handle_other(%HTTPoison.AsyncHeaders{headers: headers}, state) do
    debug("Got headers #{inspect(headers)}")

    case headers |> List.keyfind("Content-Type", 0) do
      nil ->
        {:ok, state}

      {_, value} ->
        {:ok, %{state | content_type: value}}
    end
  end


  @doc """
  Callback invoked when we receive chunk of data.

  It is forwarded to the linked destinations.
  """
  def handle_other(%HTTPoison.AsyncChunk{chunk: chunk}, %{content_type: content_type} = state) do
    debug("Got chunk #{inspect(chunk)}")

    {:send_buffer, {%Membrane.Caps{content: content_type}, chunk}, state}
  end


  @doc """
  Callback invoked when data downloading ends.

  It emits EOS downstream event. (TODO)
  """
  def handle_other(%HTTPoison.AsyncEnd{}, state) do
    debug("End of stream")

    # TODO send EOS event
    {:ok, state}
  end
end
