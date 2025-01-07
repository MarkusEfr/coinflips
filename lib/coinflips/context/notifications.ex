defmodule Coinflips.Notifications do
  import Ecto.Query, warn: false
  alias Coinflips.Repo
  alias Coinflips.Notification

  def group_notifications_by_status(notifications) do
    Enum.group_by(notifications, fn notification ->
      if notification.unread?, do: "Unreaden", else: "Readen"
    end)
    |> Enum.reverse()
  end

  def group_notifications_by_date(notifications) do
    Enum.group_by(notifications, fn notification ->
      notification.inserted_at |> Timex.format!("{0D}-{0M}-{YYYY}")
    end)
    |> Enum.reverse()
  end

  # Fetch all notifications for a specific wallet, ordered by insertion timestamp
  def get_notifications_by_wallet(wallet_address) do
    from(n in Notification,
      where: n.wallet_address == ^wallet_address,
      order_by: [desc: n.inserted_at]
    )
    |> Repo.all()
  end

  def mark_as_read(notification_id) do
    notification = Repo.get!(Notification, notification_id)

    notification
    |> Notification.changeset(%{unread?: false})
    |> Repo.update()
  end

  def mark_as_unread(notification_id) do
    notification = Repo.get!(Notification, notification_id)

    notification
    |> Notification.changeset(%{unread?: true})
    |> Repo.update()
  end

  # Mark a notification as unread
  def mark_as_unread(notification_id) do
    notification = Repo.get!(Notification, notification_id)

    notification
    |> Notification.changeset(%{status: "unread"})
    |> Repo.update()
  end

  # Create a new notification
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  def list_notifications(wallet_address, opts \\ %{}) do
    query =
      from(n in Notification,
        where: n.wallet_address == ^wallet_address,
        order_by: [desc: n.inserted_at]
      )

    case opts do
      %{unread?: true} -> query |> where([n], n.unread? == true) |> Repo.all()
      %{unread?: false} -> query |> where([n], n.unread? == false) |> Repo.all()
      _ -> Repo.all(query)
    end
  end
end
