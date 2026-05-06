package com.mywebapp.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;
import java.sql.Connection;

@RestController
@RequestMapping("/health")
public class HealthController {

    private final DataSource dataSource;

    public HealthController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @GetMapping("/alive")
    public ResponseEntity<String> alive() {
        return ResponseEntity.ok("OK");
    }

    @GetMapping("/ready")
    public ResponseEntity<String> ready() {
        try (Connection conn = dataSource.getConnection()) {
            if (!conn.isValid(2)) {
                return ResponseEntity.internalServerError()
                        .body("Database connection is not valid");
            }
            return ResponseEntity.ok("OK");
        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .body("Database unavailable: " + e.getMessage());
        }
    }
}
