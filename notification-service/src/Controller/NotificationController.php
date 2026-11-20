<?php

namespace App\Controller;

use Doctrine\DBAL\Connection;
use Doctrine\DBAL\ParameterType;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;

final class NotificationController
{
    #[Route('/api/notifications', name: 'notifications_list', methods: ['GET'])]
    public function list(Request $request, Connection $db): JsonResponse
    {
        $orderId = $request->query->all()['order_id'] ?? null;
        $sql = 'SELECT id, order_id, message, created_at FROM notifications';
        $params = [];
        $types = [];

        if ($orderId !== null) {
            if (
                !is_string($orderId)
                || !preg_match('/\A[1-9][0-9]{0,9}\z/', $orderId)
                || (int) $orderId > 2147483647
            ) {
                return new JsonResponse(['error' => 'Invalid order_id'], 400);
            }

            $sql .= ' WHERE order_id = :order_id';
            $params['order_id'] = (int) $orderId;
            $types['order_id'] = ParameterType::INTEGER;
        }

        $sql .= ' ORDER BY id';

        return new JsonResponse($db->fetchAllAssociative($sql, $params, $types));
    }
}
