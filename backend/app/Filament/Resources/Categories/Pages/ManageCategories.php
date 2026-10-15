<?php

namespace App\Filament\Resources\Categories\Pages;

use App\Filament\Resources\Categories\CategoryResource;
use App\Services\CategoryService;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ManageRecords;

class ManageCategories extends ManageRecords
{
    protected static string $resource = CategoryResource::class;

    protected function getHeaderActions(): array
    {
        return [
            CreateAction::make()
                ->label('Tambah Kategori')
                ->modalHeading('Tambah Kategori')
                // Slug dibuat server dan tidak diubah saat nama diganti.
                ->mutateDataUsing(fn (array $data): array => [
                    ...$data,
                    'slug' => app(CategoryService::class)->makeSlug($data['name']),
                ]),
        ];
    }
}
