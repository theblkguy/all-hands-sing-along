# lib/all_hands_sing_along_web/controllers/session_controller.ex
defmodule AllHandsSingAlongWeb.SessionController do
  @moduledoc """
  Sets session cookies for host/guest join, then redirects into the room LiveView.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Accounts.User
  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlong.Rooms.SessionForm

  @spec create_host(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_host(conn, params) do
    signed_in? = signed_in?(conn)
    changeset = SessionForm.host_changeset(params, signed_in: signed_in?)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, fields} ->
        case room_display_name(conn, fields) do
          nil ->
            conn
            |> put_flash(:error, "Pick a username to continue.")
            |> redirect(to: ~p"/")

          name ->
            case Rooms.create_room(conn.assigns[:current_user]) do
              {:ok, room} ->
                conn
                |> put_guest_session(name)
                |> put_session(
                  :host_tokens,
                  Map.put(host_tokens(conn), room.code, room.host_token)
                )
                |> redirect(to: ~p"/rooms/#{room.code}")

              {:error, :code_collision} ->
                conn
                |> put_flash(:error, "Couldn't create a room. Try again.")
                |> redirect(to: ~p"/")

              {:error, _changeset} ->
                conn
                |> put_flash(:error, "Couldn't create a room. Try again.")
                |> redirect(to: ~p"/")
            end
        end

      {:error, changeset} ->
        conn
        |> put_flash(:error, first_error(changeset))
        |> redirect(to: ~p"/")
    end
  end

  @spec join(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def join(conn, params) do
    signed_in? = signed_in?(conn)
    changeset = SessionForm.join_changeset(params, signed_in: signed_in?)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, fields} ->
        case room_display_name(conn, fields) do
          nil ->
            conn
            |> put_flash(:error, "Pick a username to continue.")
            |> redirect(to: ~p"/")

          name ->
            case Rooms.get_room_by_code(fields.code) do
              {:ok, room} ->
                _ = Rooms.record_membership(room, conn.assigns[:current_user])

                conn
                |> put_guest_session(name)
                |> redirect(to: ~p"/rooms/#{room.code}")

              {:error, :not_found} ->
                conn
                |> put_flash(:error, "Room not found.")
                |> redirect(to: ~p"/")
            end
        end

      {:error, changeset} ->
        conn
        |> put_flash(:error, first_error(changeset))
        |> redirect(to: ~p"/")
    end
  end

  @doc """
  Turn this browser into the host via the room's host link.

  The host token used to live only in the cookie that clicked Create room, so a
  cleared cookie, a different browser, or a phone meant losing the controls.
  Now the room page shows a link the host can save; opening it here re-grants
  host in the current session.
  """
  @spec claim_host(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def claim_host(conn, %{"code" => code, "token" => token}) do
    with {:ok, room} <- Rooms.get_room_by_code(code),
         :ok <- Rooms.authorize_host(room, token) do
      name = room_display_name(conn, %{display_name: get_session(conn, :display_name)}) || "Host"
      _ = Rooms.record_membership(room, conn.assigns[:current_user])

      conn
      |> put_guest_session(name)
      |> put_session(:host_tokens, Map.put(host_tokens(conn), room.code, room.host_token))
      |> put_flash(:info, "You're the host in this browser now.")
      |> redirect(to: ~p"/rooms/#{room.code}")
    else
      _ ->
        conn
        |> put_flash(:error, "That host link isn't valid.")
        |> redirect(to: ~p"/")
    end
  end

  defp signed_in?(conn), do: match?(%User{}, conn.assigns[:current_user])

  defp room_display_name(conn, fields) do
    case User.display_name(conn.assigns[:current_user]) do
      nil -> Map.get(fields, :display_name)
      name -> name
    end
  end

  defp put_guest_session(conn, name) do
    guest_id =
      case conn.assigns[:current_user] do
        %{id: id} -> "user-#{id}"
        _ -> get_session(conn, :guest_id) || Ecto.UUID.generate()
      end

    conn
    |> put_session(:display_name, name)
    |> put_session(:guest_id, guest_id)
  end

  defp host_tokens(conn), do: get_session(conn, :host_tokens) || %{}

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> List.first()
    |> case do
      nil -> "Invalid"
      msg -> msg
    end
  end
end
