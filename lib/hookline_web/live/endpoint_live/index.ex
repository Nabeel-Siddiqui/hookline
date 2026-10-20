defmodule HooklineWeb.EndpointLive.Index do
  use HooklineWeb, :live_view

  alias Hookline.Relay
  alias Hookline.Relay.Endpoint

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :endpoints, Relay.list_endpoints(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Endpoints") |> assign(:endpoint, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:page_title, "New Endpoint") |> assign(:endpoint, %Endpoint{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Endpoints
      <:subtitle>Every receiving URL you've created.</:subtitle>
      <:actions>
        <.link patch={~p"/endpoints/new"}>
          <.button>New endpoint</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="endpoints"
      rows={@endpoints}
      row_click={fn endpoint -> JS.navigate(~p"/endpoints/#{endpoint}") end}
    >
      <:col :let={endpoint} label="Name">{endpoint.name}</:col>
      <:col :let={endpoint} label="Receiving URL"><code>/in/{endpoint.token}</code></:col>
    </.table>

    <p :if={@endpoints == []} class="mt-6 text-sm text-zinc-500">
      No endpoints yet. Create one to get a receiving URL.
    </p>

    <.modal :if={@live_action == :new} id="endpoint-modal" show on_cancel={JS.patch(~p"/endpoints")}>
      <.live_component
        module={HooklineWeb.EndpointLive.FormComponent}
        id={:new}
        title={@page_title}
        action={@live_action}
        endpoint={@endpoint}
        current_user={@current_user}
        patch={~p"/endpoints"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_info({HooklineWeb.EndpointLive.FormComponent, {:saved, _endpoint}}, socket) do
    {:noreply, assign(socket, :endpoints, Relay.list_endpoints(socket.assigns.current_user))}
  end
end
