defmodule HooklineWeb.EndpointLive.Event do
  @moduledoc """
  One captured event: its headers and body exactly as received, and
  every delivery attempt made for it so far — live, same as the
  dashboard, so watching a replay happen doesn't need a reload either.
  """

  use HooklineWeb, :live_view

  alias Hookline.Relay

  @impl true
  def mount(%{"id" => endpoint_id, "event_id" => event_id}, _session, socket) do
    with {:ok, endpoint} <- Relay.get_endpoint(socket.assigns.current_user, endpoint_id),
         {:ok, event} <- Relay.get_event(endpoint, event_id) do
      if connected?(socket), do: Relay.subscribe_to_endpoint(endpoint)

      {:ok,
       socket
       |> assign(:endpoint, endpoint)
       |> assign(:event, event)
       |> assign(:page_title, "Event ##{event.id}")
       |> assign(:attempts, Relay.list_attempts(event))}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That event doesn't exist.")
         |> push_navigate(to: ~p"/endpoints")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Event #{@event.id}
      <:subtitle>Received {Calendar.strftime(@event.received_at, "%Y-%m-%d %H:%M:%S UTC")}</:subtitle>
      <:actions>
        <.button phx-click="replay" phx-disable-with="Replaying...">Replay</.button>
        <.back navigate={~p"/endpoints/#{@endpoint}"}>Back to {@endpoint.name}</.back>
      </:actions>
    </.header>

    <.header class="mt-10">Headers</.header>
    <ul class="mt-2 space-y-1 text-sm">
      <li :for={{key, value} <- Enum.sort(@event.headers)}>
        <span class="font-semibold text-zinc-900">{key}:</span>
        <span class="text-zinc-700">{value}</span>
      </li>
    </ul>

    <.header class="mt-10">Body</.header>
    <pre class="mt-2 rounded-lg bg-zinc-100 p-4 text-xs whitespace-pre-wrap">{@event.body}</pre>

    <.header class="mt-10">Delivery attempts</.header>
    <.table id="attempts" rows={@attempts}>
      <:col :let={attempt} label="Attempt">{attempt.attempt_number}</:col>
      <:col :let={attempt} label="Status">{attempt.status}</:col>
      <:col :let={attempt} label="Response">{attempt.response_code || attempt.error || "—"}</:col>
      <:col :let={attempt} label="When">{Calendar.strftime(attempt.attempted_at, "%H:%M:%S")}</:col>
    </.table>
    <p :if={@attempts == []} class="mt-4 text-sm text-zinc-500">
      No delivery attempts yet.
    </p>
    """
  end

  @impl true
  def handle_event("replay", _params, socket) do
    :ok = Relay.enqueue_deliveries(socket.assigns.event)
    {:noreply, put_flash(socket, :info, "Replaying this event to every active destination")}
  end

  @impl true
  def handle_info({:attempt_recorded, attempt}, socket) do
    if attempt.event_id == socket.assigns.event.id do
      {:noreply, assign(socket, :attempts, Relay.list_attempts(socket.assigns.event))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:event_captured, _event}, socket), do: {:noreply, socket}
end
