<?php

namespace App\Controller;

use App\Entity\Order;
use App\Message\OrderCreated;
use App\Message\OrderStatusChanged;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Messenger\Bridge\Amqp\Transport\AmqpStamp;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Routing\Attribute\Route;

final class OrderController
{
    #[Route('/api/orders', name: 'orders_create', methods: ['POST'])]
    public function create(
        Request $request,
        EntityManagerInterface $em,
        MessageBusInterface $bus,
    ): JsonResponse {
        $data = json_decode($request->getContent(), true);
        $customerId = $data['customer_id'] ?? null;
        $amount = $data['amount'] ?? null;

        if (
            !is_int($customerId) || $customerId < 1 || $customerId > 2147483647
            || (!is_int($amount) && !is_float($amount) && !is_string($amount))
            || !preg_match('/\A[0-9]{1,8}(?:\.[0-9]{1,2})?\z/', (string) $amount)
        ) {
            return new JsonResponse(['error' => 'Invalid customer_id or amount'], 400);
        }

        [$whole, $fraction] = array_pad(explode('.', (string) $amount, 2), 2, '');
        $amount = (int) $whole . '.' . str_pad($fraction, 2, '0');

        if ($amount === '0.00') {
            return new JsonResponse(['error' => 'Amount must be positive'], 400);
        }

        $order = new Order($customerId, $amount);
        $em->persist($order);
        $em->flush();

        $bus->dispatch(new OrderCreated(
            $order->getId(),
            $order->getCustomerId(),
            $order->getAmount(),
        ));

        return $this->orderResponse($order, 201);
    }

    #[Route('/api/orders/{id}', name: 'orders_get', requirements: ['id' => '\d{1,10}'], methods: ['GET'])]
    public function get(int $id, EntityManagerInterface $em): JsonResponse
    {
        $order = $id > 2147483647 ? null : $em->find(Order::class, $id);

        if ($order === null) {
            return new JsonResponse(['error' => 'Order not found'], 404);
        }

        return $this->orderResponse($order, 200);
    }

    #[Route('/api/orders/{id}/status', name: 'orders_change_status', requirements: ['id' => '\d{1,10}'], methods: ['PATCH'])]
    public function changeStatus(
        int $id,
        Request $request,
        EntityManagerInterface $em,
        MessageBusInterface $bus,
    ): JsonResponse {
        $data = json_decode($request->getContent(), true);
        $status = $data['status'] ?? null;

        if (!in_array($status, ['created', 'paid', 'cancelled'], true)) {
            return new JsonResponse(['error' => 'Invalid status'], 400);
        }

        $order = $id > 2147483647 ? null : $em->find(Order::class, $id);

        if ($order === null) {
            return new JsonResponse(['error' => 'Order not found'], 404);
        }

        $previousStatus = $order->getStatus();

        if ($previousStatus === $status) {
            return $this->orderResponse($order, 200);
        }

        $order->changeStatus($status);
        $em->flush();

        $bus->dispatch(
            new OrderStatusChanged($id, $previousStatus, $status),
            [new AmqpStamp('order.status_changed')],
        );

        return $this->orderResponse($order, 200);
    }

    private function orderResponse(Order $order, int $status): JsonResponse
    {
        return new JsonResponse([
            'id' => $order->getId(),
            'customer_id' => $order->getCustomerId(),
            'amount' => $order->getAmount(),
            'status' => $order->getStatus(),
            'created_at' => $order->getCreatedAt()->format(DATE_ATOM),
        ], $status);
    }
}
