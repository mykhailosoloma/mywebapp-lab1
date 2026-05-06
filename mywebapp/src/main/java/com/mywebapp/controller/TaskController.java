package com.mywebapp.controller;

import com.mywebapp.model.Task;
import com.mywebapp.service.TaskService;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
public class TaskController {

    private final TaskService taskService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    public String root() {
        return """
                <!DOCTYPE html>
                <html><head><title>mywebapp</title></head>
                <body>
                <h1>mywebapp - Task Tracker</h1>
                <h2>Available endpoints:</h2>
                <ul>
                  <li>GET /tasks - list all tasks</li>
                  <li>POST /tasks - create a new task</li>
                  <li>POST /tasks/{id}/done - mark task as done</li>
                </ul>
                </body></html>
                """;
    }

    @GetMapping("/tasks")
    public ResponseEntity<?> getTasks(
            @RequestHeader(value = "Accept", defaultValue = "application/json") String accept) {

        List<Task> tasks = taskService.getAllTasks();

        if (accept.contains("text/html")) {
            StringBuilder sb = new StringBuilder();
            sb.append("<!DOCTYPE html><html><head><title>Tasks</title></head><body>");
            sb.append("<h1>Tasks</h1>");
            sb.append("<table border=\"1\"><tr><th>id</th><th>title</th><th>status</th><th>created_at</th></tr>");
            for (Task t : tasks) {
                sb.append("<tr><td>").append(t.getId()).append("</td>")
                  .append("<td>").append(escapeHtml(t.getTitle())).append("</td>")
                  .append("<td>").append(t.getStatus()).append("</td>")
                  .append("<td>").append(t.getCreated_at().format(FMT)).append("</td></tr>");
            }
            sb.append("</table></body></html>");
            return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(sb.toString());
        }

        List<Map<String, Object>> result = tasks.stream().map(t -> Map.<String, Object>of(
                "id", t.getId(),
                "title", t.getTitle(),
                "status", t.getStatus(),
                "created_at", t.getCreated_at().format(FMT)
        )).toList();
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(result);
    }

    @PostMapping("/tasks")
    public ResponseEntity<?> createTask(
            @RequestBody Map<String, String> body,
            @RequestHeader(value = "Accept", defaultValue = "application/json") String accept) {

        String title = body.get("title");
        if (title == null || title.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "title is required"));
        }

        Task task = taskService.createTask(title);

        if (accept.contains("text/html")) {
            String html = "<!DOCTYPE html><html><head><title>Task Created</title></head><body>" +
                    "<h1>Task Created</h1>" +
                    "<table border=\"1\"><tr><th>id</th><th>title</th><th>status</th><th>created_at</th></tr>" +
                    "<tr><td>" + task.getId() + "</td><td>" + escapeHtml(task.getTitle()) + "</td><td>" +
                    task.getStatus() + "</td><td>" + task.getCreated_at().format(FMT) + "</td></tr>" +
                    "</table></body></html>";
            return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
        }

        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(Map.of(
                "id", task.getId(),
                "title", task.getTitle(),
                "status", task.getStatus(),
                "created_at", task.getCreated_at().format(FMT)
        ));
    }

    @PostMapping("/tasks/{id}/done")
    public ResponseEntity<?> markDone(
            @PathVariable Long id,
            @RequestHeader(value = "Accept", defaultValue = "application/json") String accept) {

        Optional<Task> result = taskService.markDone(id);
        if (result.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Task task = result.get();

        if (accept.contains("text/html")) {
            String html = "<!DOCTYPE html><html><head><title>Task Updated</title></head><body>" +
                    "<h1>Task marked as done</h1>" +
                    "<table border=\"1\"><tr><th>id</th><th>title</th><th>status</th><th>created_at</th></tr>" +
                    "<tr><td>" + task.getId() + "</td><td>" + escapeHtml(task.getTitle()) + "</td><td>" +
                    task.getStatus() + "</td><td>" + task.getCreated_at().format(FMT) + "</td></tr>" +
                    "</table></body></html>";
            return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
        }

        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(Map.of(
                "id", task.getId(),
                "title", task.getTitle(),
                "status", task.getStatus(),
                "created_at", task.getCreated_at().format(FMT)
        ));
    }

    private String escapeHtml(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
