<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // Tema dashboard dibangun dengan Vite (`npm run build`). Tes tidak boleh
        // bergantung pada hasil build tersebut, jadi Vite dimatikan di sini.
        $this->withoutVite();
    }
}
