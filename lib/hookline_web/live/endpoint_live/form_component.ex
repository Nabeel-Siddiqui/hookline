defmodule HooklineWeb.EndpointLive.FormComponent do
  @moduledoc """
  The "new endpoint" form, shown in a modal from `EndpointLive.Index`.
  """

  use HooklineWeb, :live_component

  alias Hookline.Relay

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>A receiving URL. Anything POSTed to it is captured as an event.</:subtitle>
      </.header>

      <.simple_form for={@form} id="endpoint-form" phx-target={@myself} phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" placeholder="Stripe prod" />
        <:actions>
          <.button phx-disable-with="Saving...">Save endpoint</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(Relay.create_endpoint_changeset(%{})))}
  end

  @impl true
  def handle_event("save", %{"endpoint" => endpoint_params}, socket) do
    case Relay.create_endpoint(socket.assigns.current_user, endpoint_params) do
      {:ok, endpoint} ->
        notify_parent({:saved, endpoint})

        {:noreply,
         socket
         |> put_flash(:info, "Endpoint created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
