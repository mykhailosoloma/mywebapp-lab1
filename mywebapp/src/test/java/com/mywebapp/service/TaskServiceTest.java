package com.mywebapp.service;

import com.mywebapp.model.Task;
import com.mywebapp.repository.TaskRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TaskServiceTest {

    @Mock
    private TaskRepository taskRepository;

    @InjectMocks
    private TaskService taskService;

    @Test
    void getAllTasksReturnsAllTasks() {
        Task t1 = makeTask(1L, "Task 1", "pending");
        Task t2 = makeTask(2L, "Task 2", "done");
        when(taskRepository.findAll()).thenReturn(List.of(t1, t2));

        List<Task> result = taskService.getAllTasks();

        assertThat(result).hasSize(2);
        assertThat(result.get(0).getTitle()).isEqualTo("Task 1");
        assertThat(result.get(1).getTitle()).isEqualTo("Task 2");
    }

    @Test
    void getAllTasksReturnsEmptyList() {
        when(taskRepository.findAll()).thenReturn(List.of());

        List<Task> result = taskService.getAllTasks();

        assertThat(result).isEmpty();
    }

    @Test
    void createTaskSavesAndReturnsTask() {
        Task saved = makeTask(1L, "My task", "pending");
        when(taskRepository.save(any(Task.class))).thenReturn(saved);

        Task result = taskService.createTask("My task");

        assertThat(result.getTitle()).isEqualTo("My task");
        assertThat(result.getStatus()).isEqualTo("pending");
        verify(taskRepository, times(1)).save(any(Task.class));
    }

    @Test
    void markDoneReturnsDoneTask() {
        Task task = makeTask(1L, "Task", "pending");
        Task updated = makeTask(1L, "Task", "done");
        when(taskRepository.findById(1L)).thenReturn(Optional.of(task));
        when(taskRepository.save(any(Task.class))).thenReturn(updated);

        Optional<Task> result = taskService.markDone(1L);

        assertThat(result).isPresent();
        assertThat(result.get().getStatus()).isEqualTo("done");
    }

    @Test
    void markDoneReturnsEmptyWhenNotFound() {
        when(taskRepository.findById(99L)).thenReturn(Optional.empty());

        Optional<Task> result = taskService.markDone(99L);

        assertThat(result).isEmpty();
    }

    private Task makeTask(Long id, String title, String status) {
        Task t = new Task();
        t.setId(id);
        t.setTitle(title);
        t.setStatus(status);
        t.setCreated_at(LocalDateTime.now());
        return t;
    }
}