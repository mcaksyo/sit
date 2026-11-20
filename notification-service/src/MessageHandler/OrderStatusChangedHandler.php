<?php

namespace App\MessageHandler;

use App\Message\OrderStatusChanged;
use App\Service\NotificationWriter;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final class OrderStatusChangedHandler
{
    public function __construct(private NotificationWriter $writer)
    {
    }

    public function __invoke(OrderStatusChanged $event): void
    {
        $this->writer->save(
            $event->orderId,
            sprintf(
                'Статус заказа №%d изменён с %s на %s',
                $event->orderId,
                $event->previousStatus,
                $event->newStatus,
            ),
            $event->eventId ?? null,
        );
    }
}
