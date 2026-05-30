package com.mywebapp.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mywebapp.model.Task;
import com.mywebapp.repository.TaskRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class TaskControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private TaskRepository taskRepository;

    @Autowired
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        taskRepository.deleteAll();
    }

    @Test
    void rootReturnsHtml() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(containsString("mywebapp")));
    }

    @Test
    void getTasksReturnsEmptyList() throws Exception {
        mockMvc.perform(get("/tasks").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void getTasksReturnsAllTasks() throws Exception {
        Task task = new Task();
        task.setTitle("Test task");
        task.setStatus("pending");
        taskRepository.save(task);

        mockMvc.perform(get("/tasks").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].title", is("Test task")))
                .andExpect(jsonPath("$[0].status", is("pending")));
    }

    @Test
    void getTasksReturnsHtmlWhenAcceptHtml() throws Exception {
        Task task = new Task();
        task.setTitle("Html task");
        task.setStatus("pending");
        taskRepository.save(task);

        mockMvc.perform(get("/tasks").accept(MediaType.TEXT_HTML))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(containsString("Html task")));
    }

    @Test
    void createTaskSuccessfully() throws Exception {
        String body = objectMapper.writeValueAsString(Map.of("title", "New task"));

        mockMvc.perform(post("/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .accept(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title", is("New task")))
                .andExpect(jsonPath("$.status", is("pending")))
                .andExpect(jsonPath("$.id", notNullValue()));
    }

    @Test
    void createTaskWithEmptyTitleReturnsBadRequest() throws Exception {
        String body = objectMapper.writeValueAsString(Map.of("title", ""));

        mockMvc.perform(post("/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error", is("title is required")));
    }

    @Test
    void createTaskWithoutTitleReturnsBadRequest() throws Exception {
        String body = objectMapper.writeValueAsString(Map.of());

        mockMvc.perform(post("/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isBadRequest());
    }

    @Test
    void createTaskReturnsHtmlWhenAcceptHtml() throws Exception {
        String body = objectMapper.writeValueAsString(Map.of("title", "Html task"));

        mockMvc.perform(post("/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .accept(MediaType.TEXT_HTML)
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(containsString("Html task")));
    }

    @Test
    void markDoneSuccessfully() throws Exception {
        Task task = new Task();
        task.setTitle("Task to complete");
        task.setStatus("pending");
        Task saved = taskRepository.save(task);

        mockMvc.perform(post("/tasks/" + saved.getId() + "/done")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("done")))
                .andExpect(jsonPath("$.id", is(saved.getId().intValue())));
    }

    @Test
    void markDoneNotFoundReturns404() throws Exception {
        mockMvc.perform(post("/tasks/99999/done")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isNotFound());
    }

    @Test
    void markDoneReturnsHtmlWhenAcceptHtml() throws Exception {
        Task task = new Task();
        task.setTitle("Html done task");
        task.setStatus("pending");
        Task saved = taskRepository.save(task);

        mockMvc.perform(post("/tasks/" + saved.getId() + "/done")
                        .accept(MediaType.TEXT_HTML))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(containsString("Html done task")));
    }
}