<?php

namespace App\Message;

final class OrderStatusChanged
{
    public readonly string $eventId;

    public function __construct(
        public readonly int $orderId,
        public readonly string $previousStatus,
        public readonly string $newStatus,
        ?string $eventId = null,
    ) {
        $this->eventId = $eventId ?? bin2hex(random_bytes(16));
    }
}
