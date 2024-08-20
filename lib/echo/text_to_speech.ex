defmodule Echo.TextToSpeech do
  @moduledoc """
  Generic TTS module.
  """
  alias Echo.Client.ElevenLabs

  @separators [".", ",", "?", "!", ";", ":", "—", "-", "(", ")", "[", "]", "}", " "]
  @max_retries 3
  @retry_delay 1000

  @doc """
  Consumes an Enumerable (such as a stream) of text
  into speech, applying `fun` to each audio element.

  Returns the spoken text contained within `enumerable`.
  """
  def stream(enumerable, pid) do
    result =
      enumerable
      |> group_tokens()
      |> Stream.map(fn text ->
        text = IO.iodata_to_binary(text)
        send_with_retry(pid, text)
        text
      end)
      |> Enum.join()

    flush_with_retry(pid)

    result
  end

  defp group_tokens(stream) do
    Stream.transform(stream, {[], []}, fn item, {current_chunk, _acc} ->
      updated_chunk = [current_chunk, item]

      if String.ends_with?(item, @separators) do
        {[updated_chunk], {[], []}}
      else
        {[], {updated_chunk, []}}
      end
    end)
  end

  defp send_with_retry(pid, text, retries \\ 0)

  defp send_with_retry(_pid, _text, retries) when retries >= @max_retries do
    Logger.error("Max retries reached. Unable to send text.")
    {:error, :max_retries_reached}
  end

  defp send_with_retry(pid, text, retries) do
    case ElevenLabs.WebSocket.send(pid, text) do
      :ok ->
        :ok

      {:error, :not_alive} ->
        Logger.warn("WebSocket not alive. Retrying in #{@retry_delay}ms...")
        Process.sleep(@retry_delay)
        send_with_retry(pid, text, retries + 1)

      error ->
        Logger.error("Unexpected error: #{inspect(error)}")
        {:error, error}
    end
  end

  defp flush_with_retry(pid, retries \\ 0)

  defp flush_with_retry(_pid, retries) when retries >= @max_retries do
    Logger.error("Max retries reached. Unable to flush.")
    {:error, :max_retries_reached}
  end

  defp flush_with_retry(pid, retries) do
    try do
      ElevenLabs.WebSocket.flush(pid)
      :ok
    rescue
      error ->
        Logger.warn(
          "Error flushing WebSocket: #{inspect(error)}. Retrying in #{@retry_delay}ms..."
        )

        Process.sleep(@retry_delay)
        flush_with_retry(pid, retries + 1)
    end
  end
end
