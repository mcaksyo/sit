<?php

namespace App\MessageHandler;

use App\Message\OrderCreated;
use App\Service\NotificationWriter;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final class OrderCreatedHandler
{
    public function __construct(private NotificationWriter $writer)
    {
    }

    public function __invoke(OrderCreated $event): void
    {
        $this->writer->save(
            $event->orderId,
            sprintf('Создан заказ №%d на сумму %s', $event->orderId, $event->amount),
            $event->eventId ?? null,
        );
    }
}
