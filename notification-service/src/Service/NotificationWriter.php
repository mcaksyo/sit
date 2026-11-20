<?php

namespace App\Service;

use Doctrine\DBAL\Connection;

final class NotificationWriter
{
    public function __construct(private Connection $db)
    {
    }

    public function save(int $orderId, string $message, ?string $eventId): void
    {
        $this->db->executeStatement(
            <<<'SQL'
                INSERT INTO notifications (order_id, message, created_at, event_id)
                VALUES (:order_id, :message, CURRENT_TIMESTAMP AT TIME ZONE 'UTC', :event_id)
                ON CONFLICT (event_id) DO NOTHING
                SQL,
            [
                'order_id' => $orderId,
                'message' => $message,
                'event_id' => $eventId,
            ],
        );
    }
}
