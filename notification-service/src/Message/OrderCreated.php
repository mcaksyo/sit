<?php

namespace App\Message;

final class OrderCreated
{
    public readonly string $eventId;

    public function __construct(
        public readonly int $orderId,
        public readonly int $customerId,
        public readonly string $amount,
        ?string $eventId = null,
    ) {
        $this->eventId = $eventId ?? bin2hex(random_bytes(16));
    }
}
